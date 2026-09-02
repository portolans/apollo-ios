import Foundation

// MARK: - Client protocol

/// Protocol allowing alternative implementations of websockets beyond `ApolloWebSocket`.
public protocol WebSocketClient: AnyObject {
  
  /// The URLRequest used on connection.
  var request: URLRequest { get set }

  /// The delegate that will receive networking event updates for this websocket client.
  ///
  /// - Note: The `WebSocketTransport` will set itself as the delgate for the client. Consumers
  /// should set themselves as the delegate for the `WebSocketTransport` to observe events.  
  var delegate: (any WebSocketClientDelegate)? { get set }

  /// `DispatchQueue` where the websocket client should call all delegate callbacks.
  var callbackQueue: DispatchQueue { get set }

  /// Connects to the websocket server.
  ///
  /// - Note: This should be implemented to connect the websocket on a background thread.
  func connect()

  /// Disconnects from the websocket server.
  func disconnect(forceTimeout: TimeInterval?)

  /// Writes ping data to the websocket.
  ///
  /// - Parameter completion: Called with `nil` once the peer's pong arrives, or with the error if the
  ///   ping could not be sent — including when no socket is currently open. Never called if the
  ///   socket is half-open: the frame is written but no pong ever comes, so a caller probing for
  ///   liveness must bound its own wait.
  func write(ping: Data, completion: (((any Error)?) -> Void)?)

  /// Writes a string to the websocket.
  func write(string: String)

}

/// The delegate for a `WebSocketClient` to recieve notification of socket events.
public protocol WebSocketClientDelegate: AnyObject {

  /// The websocket client has started a connection to the server.
  /// - Parameter socket: The `WebSocketClient` that sent the delegate event.
  func websocketDidConnect(socket: any WebSocketClient)

  /// The websocket client has disconnected from the server.
  /// - Parameters:
  ///   - socket: The `WebSocketClient` that sent the delegate event.
  ///   - error: An optional error if an error occured.
  func websocketDidDisconnect(socket: any WebSocketClient, error: (any Error)?)

  /// The websocket client received message text from the server
  /// - Parameters:
  ///   - socket: The `WebSocketClient` that sent the delegate event.
  ///   - text: The text received from the server.
  func websocketDidReceiveMessage(socket: any WebSocketClient, text: String)

  /// The websocket client received data from the server
  /// - Parameters:
  ///   - socket: The `WebSocketClient` that sent the delegate event.
  ///   - data: The data received from the server.
  func websocketDidReceiveData(socket: any WebSocketClient, data: Data)
}
