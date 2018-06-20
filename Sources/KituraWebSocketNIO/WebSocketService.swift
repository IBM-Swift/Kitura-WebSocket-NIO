import Foundation

public protocol WebSocketService: class {

    func connected(connection: WebSocketConnection)

    func disconnected(connection: WebSocketConnection, reason: WebSocketCloseReasonCode)

    func received(message: Data, from: WebSocketConnection)

    func received(message: String, from: WebSocketConnection)

}
