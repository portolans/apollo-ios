import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

/// A marker protocol to set up an object to pass through the request chain.
///
/// Used to allow additional context-specific information to pass the length of the request chain.
///
/// This allows the various interceptors to make modifications, or perform actions, with information
/// that they cannot get just from the existing operation. It can be anything that conforms to this protocol.
public protocol RequestContext {
  /// Called by `WebSocketTransport` once the socket carrying this request's subscription has
  /// reconnected. The server dropped every subscription with the old connection, and the transport
  /// has forgotten this one rather than re-send the frame it first wrote — that would subscribe
  /// again from the state the operation had *then*, a stale position for a subscription that
  /// resumes from a cursor. Subscribe again from here, from your own current state. Called on the
  /// transport's processing queue; the original `Cancellable` is inert by then.
  ///
  /// `nil`, the default, means a subscription sent with this context is forgotten on reconnect and
  /// receives nothing further. Queries and mutations never consult it.
  var webSocketDidReconnect: (@Sendable () -> Void)? { get }
}

extension RequestContext {
  public var webSocketDidReconnect: (@Sendable () -> Void)? { nil }
}

/// A request context specialization protocol that specifies options for configuring the timeout of a `URLRequest`.
///
/// A `RequestContext` object can conform to this protocol to provide a custom `requestTimeout` for an individual
/// request. If the `RequestContext` for a request does not conform to this protocol, the default request timeout
/// of `URLRequest` will be used.
public protocol RequestContextTimeoutConfigurable: RequestContext {
  /// The timeout interval specifies the limit on the idle interval allotted to a request in the process of
  /// loading. This timeout interval is measured in seconds.
  ///
  /// The value of this property will be set as the `timeoutInterval` on the `URLRequest` created for this GraphQL request.
  var requestTimeout: TimeInterval { get }
}
