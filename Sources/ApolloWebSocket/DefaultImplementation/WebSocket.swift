import Foundation
import os

// MARK: - SOCKSProxyable

public protocol SOCKSProxyable {
	/// Determines whether a SOCKS proxy is enabled on the underlying request.
	/// Mostly useful for debugging with tools like Charles Proxy.
	var enableSOCKSProxy: Bool { get set }
}

// MARK: - WebSocket

public final class WebSocket: NSObject, WebSocketClient, SOCKSProxyable {

	// MARK: Public Types

	public struct WSError: Swift.Error {
		public enum ErrorType {
			case closeError
		}

		public let type: ErrorType
		public let message: String
		public let code: Int
	}

	/// The GraphQL over WebSocket protocols supported by apollo-ios.
	public enum WSProtocol: CustomStringConvertible {
		/// WebSocket protocol `graphql-ws`. This is implemented by the [subscriptions-transport-ws](https://github.com/apollographql/subscriptions-transport-ws)
		/// and AWS AppSync libraries.
		case graphql_ws
		/// WebSocket protocol `graphql-transport-ws`. This is implemented by the [graphql-ws](https://github.com/enisdenjo/graphql-ws)
		/// library.
		case graphql_transport_ws

		public var description: String {
			switch self {
			case .graphql_ws: return "graphql-ws"
			case .graphql_transport_ws: return "graphql-transport-ws"
			}
		}
	}

	@_spi(Testable)
	public struct Constants {
		public static let headerWSProtocolName = "Sec-WebSocket-Protocol"
	}

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
	public init(request: URLRequest, protocol: WSProtocol) {
		var request = request
		request.setValue(`protocol`.description, forHTTPHeaderField: Constants.headerWSProtocolName)
		self.request = request
	}

	/// Convenience initializer to specify the URL and web socket protocol.
	///
	/// - Parameters:
	///   - url: The destination URL to connect to.
	///   - protocol: Protocol to use for communication over the web socket.
	public convenience init(url: URL, protocol: WSProtocol) {
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
		state.withLock {
			$0.session = session
			$0.task = task
		}
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
					self.forceDisconnect()
				}
			}
		default:
			forceDisconnect()
		}
	}

	public func write(string: String) {
		let currentTask: URLSessionWebSocketTask? = state.withLock { $0.task }
		currentTask?.send(.string(string)) { [weak self] error in
			if let error {
				self?.handleError(error)
			}
		}
	}

	public func write(ping: Data, completion: (() -> Void)? = nil) {
		let currentTask: URLSessionWebSocketTask? = state.withLock { $0.task }
		currentTask?.sendPing { [weak self] error in
			if let error {
				self?.handleError(error)
			}
			completion?()
		}
	}

	// MARK: Private

	private func forceDisconnect() {
		tearDown()
	}

	private func startReceiveLoop() {
		let currentTask: URLSessionWebSocketTask? = state.withLock { $0.task }
		currentTask?.receive { [weak self] result in
			guard let self else { return }
			switch result {
			case .success(let message):
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

			case .failure(let error):
				self.handleError(error)
			}
		}
	}

	private func handleError(_ error: any Error) {
		// URLSessionWebSocketTask delivers errors through both the receive loop and the
		// delegate's didCompleteWithError. The delegate handles disconnect notification,
		// so we don't duplicate it here.
	}

	private func tearDown() {
		let sessionToInvalidate: URLSession? = state.withLock {
			$0.isConnected = false
			let s = $0.session
			$0.session = nil
			$0.task = nil
			return s
		}
		sessionToInvalidate?.invalidateAndCancel()
	}

	deinit {
		state.withLock {
			$0.task?.cancel()
			$0.session?.invalidateAndCancel()
		}
	}
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocket: URLSessionWebSocketDelegate {

	public func urlSession(
		_ session: URLSession,
		webSocketTask: URLSessionWebSocketTask,
		didOpenWithProtocol protocol: String?
	) {
		state.withLock { $0.isConnected = true }
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
		tearDown()
		callbackQueue.async { [weak self] in
			guard let self else { return }
			self.delegate?.websocketDidDisconnect(socket: self, error: nil)
		}
	}

	public func urlSession(
		_ session: URLSession,
		task: URLSessionTask,
		didCompleteWithError error: (any Error)?
	) {
		guard error != nil else { return }
		tearDown()
		callbackQueue.async { [weak self] in
			guard let self else { return }
			self.delegate?.websocketDidDisconnect(socket: self, error: error)
		}
	}
}
