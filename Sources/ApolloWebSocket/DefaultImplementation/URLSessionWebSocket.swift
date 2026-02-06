import Foundation
import os

// MARK: - URLSessionWebSocket

public final class URLSessionWebSocket: NSObject, WebSocketClient, SOCKSProxyable {

	// MARK: WebSocketClient

	public var request: URLRequest
	public weak var delegate: (any WebSocketClientDelegate)?
	public var callbackQueue = DispatchQueue.main

	public var isConnected: Bool {
		state.withLock { $0.isConnected }
	}

	// MARK: SOCKSProxyable

	public var enableSOCKSProxy = false

	// MARK: Private Properties

	private struct State {
		var session: URLSession?
		var task: URLSessionWebSocketTask?
		var isConnected = false
	}

	private let state = OSAllocatedUnfairLock<State>(initialState: .init())

	// MARK: Initialization

	/// Designated initializer.
	///
	/// - Parameters:
	///   - request: A URL request object that provides request-specific information such as the URL.
	///   - protocol: Protocol to use for communication over the web socket.
	public init(request: URLRequest, protocol: WebSocket.WSProtocol) {
		var request = request
		request.setValue(`protocol`.description, forHTTPHeaderField: WebSocket.Constants.headerWSProtocolName)
		self.request = request
	}

	/// Convenience initializer to specify the URL and web socket protocol.
	///
	/// - Parameters:
	///   - url: The destination URL to connect to.
	///   - protocol: Protocol to use for communication over the web socket.
	public convenience init(url: URL, protocol: WebSocket.WSProtocol) {
		var request = URLRequest(url: url)
		request.timeoutInterval = 5
		self.init(request: request, protocol: `protocol`)
	}

	// MARK: WebSocketClient

	public func connect() {
		let configuration = URLSessionConfiguration.default
		if enableSOCKSProxy, let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] {
			configuration.connectionProxyDictionary = proxySettings
		}
		let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
		let task = session.webSocketTask(with: request)
		// Invalidate any previous session to break the URLSession -> delegate retain cycle.
		let previousSession: URLSession? = state.withLock {
			let old = $0.session
			$0.session = session
			$0.task = task
			return old
		}
		previousSession?.invalidateAndCancel()
		task.resume()
	}

	public func disconnect(forceTimeout: TimeInterval?) {
		let currentTask: URLSessionWebSocketTask? = state.withLock { $0.task }
		switch forceTimeout {
		case .none:
			currentTask?.cancel(with: .normalClosure, reason: nil)
		case .some(let timeout) where timeout > 0:
			currentTask?.cancel(with: .normalClosure, reason: nil)
			callbackQueue.asyncAfter(deadline: .now() + timeout) { [weak self] in
				guard let self else { return }
				let shouldForce: Bool = self.state.withLock { $0.task === currentTask }
				if shouldForce {
					self.tearDown()
				}
			}
		default:
			tearDown()
		}
	}

	public func write(string: String) {
		let currentTask: URLSessionWebSocketTask? = state.withLock { $0.task }
		currentTask?.send(.string(string)) { _ in }
	}

	public func write(ping: Data, completion: (() -> Void)? = nil) {
		// URLSessionWebSocketTask.sendPing does not support custom ping payloads.
		// Apollo never sends non-empty pings – this assert guards against future misuse.
		assert(ping.isEmpty, "URLSessionWebSocketTask does not support custom ping payloads")
		let currentTask: URLSessionWebSocketTask? = state.withLock { $0.task }
		currentTask?.sendPing { _ in
			completion?()
		}
	}

	// MARK: Private

	private func startReceiveLoop() {
		let currentTask: URLSessionWebSocketTask? = state.withLock { $0.task }
		currentTask?.receive { [weak self] result in
			guard let self else { return }
			switch result {
			case .success(let message):
				// Verify this task is still current before delivering message.
				// A reconnection may have created a new task while this receive was pending.
				let isCurrentTask = self.state.withLock { $0.task === currentTask }
				guard isCurrentTask else { return }

				self.callbackQueue.async {
					switch message {
					case .string(let text):
						self.delegate?.websocketDidReceiveMessage(socket: self, text: text)
					case .data(let data):
						self.delegate?.websocketDidReceiveData(socket: self, data: data)
					@unknown default:
						break
					}
				}
				self.startReceiveLoop()

			case .failure:
				// URLSessionWebSocketTask delivers errors through the delegate's
				// didCompleteWithError, which handles disconnect notification.
				break
			}
		}
	}

	private func tearDown() {
		let sessionToInvalidate: URLSession? = state.withLock {
			$0.isConnected = false
			let s = $0.session
			$0.session = nil
			$0.task = nil
			return s
		}
		// Only notify delegate if there was actually a session to tear down.
		guard let sessionToInvalidate else { return }

		sessionToInvalidate.invalidateAndCancel()
		// Notify delegate since invalidateAndCancel() triggers URLSession delegate callbacks
		// asynchronously, and our session check in those callbacks will fail (we nil'd the session above).
		callbackQueue.async { [weak self] in
			guard let self else { return }
			self.delegate?.websocketDidDisconnect(socket: self, error: nil)
		}
	}

	private func cleanupSession(_ session: URLSession, error: (any Error)?) {
		let sessionToInvalidate: URLSession? = state.withLock {
			guard $0.session === session else { return nil }
			$0.isConnected = false
			let s = $0.session
			$0.session = nil
			$0.task = nil
			return s
		}
		guard let sessionToInvalidate else { return }
		sessionToInvalidate.invalidateAndCancel()
		callbackQueue.async { [weak self] in
			guard let self else { return }
			self.delegate?.websocketDidDisconnect(socket: self, error: error)
		}
	}

	deinit {
		state.withLock {
			$0.task?.cancel()
			$0.session?.invalidateAndCancel()
		}
	}
}

// MARK: - URLSessionWebSocketDelegate

extension URLSessionWebSocket: URLSessionWebSocketDelegate {

	public func urlSession(
		_ session: URLSession,
		webSocketTask: URLSessionWebSocketTask,
		didOpenWithProtocol protocol: String?
	) {
		let isCurrent = state.withLock {
			guard $0.session === session else { return false }
			$0.isConnected = true
			return true
		}
		guard isCurrent else { return }
		startReceiveLoop()
		callbackQueue.async { [weak self] in
			guard let self else { return }
			self.delegate?.websocketDidConnect(socket: self)
		}
	}

	public func urlSession(
		_ session: URLSession,
		webSocketTask: URLSessionWebSocketTask,
		didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
		reason: Data?
	) {
		cleanupSession(session, error: nil)
	}

	public func urlSession(
		_ session: URLSession,
		task: URLSessionTask,
		didCompleteWithError error: (any Error)?
	) {
		guard error != nil else { return }
		cleanupSession(session, error: error)
	}
}
