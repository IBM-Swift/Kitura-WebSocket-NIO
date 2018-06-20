
/// Main class for the Kitura-WebSocket API. Used to register `WebSocketService` classes
/// that will handle WebSocket connections for specific paths.
public class WebSocket {
    static let factory = WSConnectionUpgradeFactory()

    /// Register a `WebSocketService` for a specific path
    ///
    /// - Parameter service: The `WebSocketService` being registered.
    /// - Parameter onPath: The path that will be in the HTTP "Upgrade" request. Used
    ///                     to connect the upgrade request with a specific `WebSocketService`
    ///                     Caps-insensitive.
    public static func register(service: WebSocketService, onPath path: String) {
        factory.register(service: service, onPath: path.lowercased())
    }
    
    /// Unregister a `WebSocketService` for a specific path
    ///
    /// - Parameter path: The path on which the `WebSocketService` being unregistered,
    ///                  was registered on.
    public static func unregister(path: String) {
    }
}
