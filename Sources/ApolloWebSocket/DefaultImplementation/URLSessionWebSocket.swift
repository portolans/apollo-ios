import Foundation
import os

// MARK: - SOCKSProxyable

public protocol SOCKSProxyable {
	/// Determines whether a SOCKS proxy is enabled on the underlying request.
	/// Mostly useful for debugging with tools like Charles Proxy.
	var enableSOCKSProxy: Bool { get set }
}

// MARK: - WebSocketClosedByPeerError

/// The peer closed the WebSocket while we still considered it live.
///
/// Surfaced as an error so subscribers hear about it. A close is not a failure of the socket
/// layer — the transport reconnects either way — but it IS the end of every subscription that was
/// running on it, and only the subscriber can re-establish those against its own current state. A
/// close reported as a clean shutdown leaves them believing they are still subscribed, so events
/// after it are lost with nothing to notice.
///
/// Carries the code and reason because they say what to do: a `graphql-transport-ws` server closes
/// with 4400-series codes for protocol and auth problems (4408 for a missing `connection_init`,
/// 4401 unauthorized), which a caller may want to treat differently from a transport-level close.
public struct WebSocketClosedByPeerError: Error, CustomStringConvertible {
	/// The RFC 6455 close code the peer sent.
	public let closeCode: URLSessionWebSocketTask.CloseCode
	/// The peer's reason phrase, when it sent one and it decoded as UTF-8.
	public let reason: String?

	public init(closeCode: URLSessionWebSocketTask.CloseCode, reason: String?) {
		self.closeCode = closeCode
		self.reason = reason
	}

	public var description: String {
		let code = "WebSocket closed by peer (code \(closeCode.rawValue)"
		guard let reason, !reason.isEmpty else { return code + ")" }
		return code + ": \(reason))"
	}
}

// MARK: - WSProtocol

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

// MARK: - WebSocketConstants

@_spi(Testable)
public enum WebSocketConstants {
	public static let headerWSProtocolName = "Sec-WebSocket-Protocol"
}

// MARK: - URLSessionWebSocket

public final class URLSessionWebSocket: NSObject, WebSocketClient, SOCKSProxyable {

	// MARK: WebSocketClient

	public var request: URLRequest
	public weak var delegate: (any WebSocketClientDelegate)?
	public var callbackQueue = DispatchQueue.main

	public var isConnected: Bool {
		state.withLock { $0.connectionState == .connected }
	}

	// MARK: SOCKSProxyable

	public var enableSOCKSProxy = false

	// MARK: Private Properties

	private enum ConnectionState {
		case idle
		case connecting
		case connected
	}

	private struct State {
		var session: URLSession?
		var task: URLSessionWebSocketTask?
		var connectionState: ConnectionState = .idle
		/// Monotonically increasing counter to distinguish connect() generations.
		var connectGeneration: UInt64 = 0
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
		request.setValue(`protocol`.description, forHTTPHeaderField: WebSocketConstants.headerWSProtocolName)
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
		// Atomically check idle, claim .connecting, and capture the generation
		// so the second lock can verify no disconnect()/connect() cycle intervened.
		let generation: UInt64? = state.withLock {
			guard $0.connectionState == .idle else { return nil }
			$0.connectionState = .connecting
			$0.connectGeneration &+= 1
			return $0.connectGeneration
		}
		guard let generation else { return }

		let configuration = URLSessionConfiguration.default
		if enableSOCKSProxy, let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] {
			configuration.connectionProxyDictionary = proxySettings
		}
		let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
		let task = session.webSocketTask(with: request)
		// URLSessionWebSocketTask defaults to a 1MB maximum incoming message size.
		// The legacy Starscream WebSocket had no such limit, so we set a high ceiling
		// to avoid "Message too long" failures on large GraphQL subscription payloads.
		task.maximumMessageSize = 10 * 1_024 * 1_024

		// Store the new session/task, but only if this is still our generation.
		// A concurrent disconnect() → connect() cycle would have bumped the
		// generation, so we abort rather than overwriting the newer attempt.
		let (proceed, previousSession): (Bool, URLSession?) = state.withLock {
			guard $0.connectGeneration == generation else { return (false, nil) }
			let old = $0.session
			$0.session = session
			$0.task = task
			return (true, old)
		}
		guard proceed else {
			session.invalidateAndCancel()
			return
		}
		previousSession?.invalidateAndCancel()
		task.resume()
	}

	public func disconnect(forceTimeout: TimeInterval?) {
		// Atomically check non-idle, grab the task/session, and transition to
		// .idle so a subsequent connect() can proceed immediately. The old
		// session is kept alive (locally) for the close handshake.
		let (task, oldSession): (URLSessionWebSocketTask?, URLSession?) = state.withLock {
			guard $0.connectionState != .idle else { return (nil, nil) }
			let t = $0.task
			let s = $0.session
			$0.connectionState = .idle
			$0.session = nil
			$0.task = nil
			return (t, s)
		}
		guard let oldSession else { return }

		callbackQueue.async { [weak self] in
			guard let self else { return }
			self.delegate?.websocketDidDisconnect(socket: self, error: nil)
		}

		switch forceTimeout {
		case .none:
			// Graceful close: send close frame and let the session finish
			// outstanding work (the close handshake) before invalidating.
			task?.cancel(with: .normalClosure, reason: nil)
			oldSession.finishTasksAndInvalidate()
		case .some(let timeout) where timeout > 0:
			// Send close frame, then force-kill after the timeout to ensure
			// teardown completes before the OS suspends the app on background.
			task?.cancel(with: .normalClosure, reason: nil)
			callbackQueue.asyncAfter(deadline: .now() + timeout) {
				oldSession.invalidateAndCancel()
			}
		default:
			// forceTimeout == 0: skip the close frame for fastest possible teardown.
			oldSession.invalidateAndCancel()
		}
	}

	public func write(string: String) {
		let (currentSession, currentTask): (URLSession?, URLSessionWebSocketTask?) = state.withLock {
			($0.session, $0.task)
		}
		currentTask?.send(.string(string)) { [weak self] error in
			guard let self, let error, let currentSession else { return }
			// A failed send is one of the only signals that a half-open socket
			// (peer/network gone but the OS never delivered a close or error) is
			// actually dead. Without surfacing it, the read loop hangs forever, so
			// websocketDidDisconnect never fires and Apollo never reconnects. Route
			// genuine failures through the same teardown path as didCompleteWithError.
			//
			// The real protection against self-triggering a spurious reconnect is
			// cleanupSession's session-identity guard ($0.session === session):
			// every self-inflicted teardown (disconnect(), connect()'s abort)
			// clears or replaces state.session before cancelling, so a leaked
			// cancellation error from our own invalidateAndCancel() lands on a
			// stale session and no-ops. The .cancelled check below is only a cheap
			// fast-path — it does not catch every case, since URLSession often
			// delivers task cancellations as NSPOSIXErrorDomain ECANCELED rather
			// than URLError.cancelled — kept consistent with the identical filter
			// in didCompleteWithError.
			guard (error as? URLError)?.code != .cancelled else { return }
			self.cleanupSession(currentSession, error: error)
		}
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

	private func cleanupSession(_ session: URLSession, error: (any Error)?) {
		let sessionToInvalidate: URLSession? = state.withLock {
			guard $0.session === session else { return nil }
			$0.connectionState = .idle
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
			$0.connectionState = .connected
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
		// Report the close rather than treating it as a clean shutdown. `cleanupSession` ignores a
		// session we already replaced, and `disconnect()` clears `state.session` before its own
		// close handshake — so anything arriving here for the CURRENT session was closed by the
		// peer, not by us, and subscribers need to hear about it.
		cleanupSession(
			session,
			error: WebSocketClosedByPeerError(
				closeCode: closeCode,
				reason: reason.flatMap { String(data: $0, encoding: .utf8) }
			)
		)
	}

	public func urlSession(
		_ session: URLSession,
		task: URLSessionTask,
		didCompleteWithError error: (any Error)?
	) {
		guard let error else { return }
		// Cancellation errors are triggered by our own disconnect()/connect() calls
		// via invalidateAndCancel(). These are intentional disconnects, not failures.
		let reportedError: (any Error)? = (error as? URLError)?.code == .cancelled ? nil : error
		cleanupSession(session, error: reportedError)
	}
}
