#if !COCOAPODS
import Apollo
import ApolloAPI
#endif
import Foundation

/// A task to wrap sending/canceling operations over a websocket.
final class WebSocketTask<Operation: GraphQLOperation>: Cancellable {
  let sequenceNumber : String?
  let transport: WebSocketTransport

  /// Designated initializer
  ///
  /// - Parameter ws: The `WebSocketTransport` to use for this task
  /// - Parameter operation: The `GraphQLOperation` to use
  /// - Parameter reconnectHandling: How to re-establish this operation once the socket reconnects,
  ///   when its request context asked to be called back.
  /// - Parameter completionHandler: A completion handler to fire when the operation has a result.
  init(_ ws: WebSocketTransport,
       _ operation: Operation,
       reconnectHandling: (any WebSocketReconnectHandling)?,
       _ completionHandler: @escaping (_ result: Result<JSONObject, any Error>) -> Void) {
    sequenceNumber = ws.sendHelper(operation: operation, reconnectHandling: reconnectHandling, resultHandler: completionHandler)
    transport = ws
  }

  public func cancel() {
    if let sequenceNumber = sequenceNumber {
      transport.unsubscribe(sequenceNumber)
    }
  }

  // Unsubscribes from further results from this task.
  public func unsubscribe() {
    cancel()
  }
}
