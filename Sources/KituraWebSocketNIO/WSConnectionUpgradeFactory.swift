import Foundation
import KituraNIO
import NIO
import NIOHTTP1

public class WSConnectionUpgradeFactory: ProtocolHandlerFactory {
    private var registry = Dictionary<String, WebSocketService>()

    public let name = "websocket"

    init() {
        ConnectionUpgrader.register(handlerFactory: self)
    }

    public func handler(for request: HTTPRequestHead) -> ChannelHandler {
        let service = registry[request.uri]

        let connection = WebSocketConnection(request: request)
        connection.service = service


        return connection
    }

    func register(service: WebSocketService, onPath: String) {
        let path: String
        if onPath.hasPrefix("/") {
            path = onPath
        }
        else {
            path = "/" + onPath
        }
        registry[path] = service
    }

    func unregister(path thePath: String) {
        let path: String
        if thePath.hasPrefix("/") {
            path = thePath
        }
        else {
            path = "/" + thePath
        }
        registry.removeValue(forKey: path)
    }

    /// Clear the `WebSocketService` registry. Used in testing.
    func clear() {
        registry.removeAll()
    }
}
