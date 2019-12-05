import XCTest
import Foundation
import Dispatch
import NIO
import NIOWebSocket
import NIOHTTP1

import LoggerAPI
@testable import KituraWebSocket
import Socket

class ConnectionTests: KituraTest {

    static var allTests: [(String, (ConnectionTests) -> () throws -> Void)] {
        return [
            ("testDisconnectCallback", testDisconnectCallback)
        ]
    }
    func testDisconnectCallback() {
        let service = TestWebSocketService( closeReason: .normal, testServerRequest: false, pingMessage: nil, testQueryParams: false, connectionTimeout: nil)
        WebSocket.register(service: service, onPath: servicePath)
        performServerTest { expectation in
            for _ in 0...100 {
                guard let client = WebSocketClient(host: "localhost", port:8080 , uri: self.servicePath, requestKey: self.secWebKey) else { return }
                client.connect()
                client.onClose { channel, _ in
                    service.queue.sync {
                        if service.disconnectClientId.count == 100 {
                        XCTAssertEqual(service.connectClientId.sorted(),service.disconnectClientId.sorted(), "Client IDs from connect weren't client IDs from disconnect")
                        expectation.fulfill()
                        } else { return }
                    }
                }
                client.close()
            }
        }
    }
}
