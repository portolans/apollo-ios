#if !COCOAPODS
import Apollo
#endif
import Foundation

/// A request context for a subscription that subscribes again itself when the WebSocket carrying it
/// reconnects.
///
/// The server drops every subscription along with the connection it ran on. Re-sending the frame
/// the transport first wrote would subscribe again from the state the operation had *then* — for a
/// subscription that resumes from a cursor, a stale position. So on reconnect the transport instead
/// forgets the subscription and calls `didReconnect`, and the owner subscribes again from its own
/// current state. Pass a conforming context to `ApolloClient.subscribe(subscription:context:...)`.
///
/// A subscription sent without a conforming context is forgotten on reconnect and receives nothing
/// further.
public protocol WebSocketReconnectHandling: RequestContext {
  /// Called on the transport's processing queue once the socket has reconnected and the transport
  /// has forgotten the subscription. Subscribe again from here; the original `Cancellable` is inert.
  var didReconnect: @Sendable () -> Void { get }
}
