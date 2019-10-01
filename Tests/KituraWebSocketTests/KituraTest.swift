/**
 * Copyright IBM Corporation 2016
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import XCTest
import LoggerAPI
@testable import KituraWebSocket
import KituraNet
import Cryptor
import NIO
import NIOHTTP1
import NIOWebSocket
import Foundation
import Dispatch

class KituraTest: XCTestCase {

    private static let initOnce: () = {
        PrintLogger.use(colored: true)
    }()

    override func setUp() {
        super.setUp()
        //KituraTest.initOnce
    }

    private static var wsGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    var secWebKey = "test"

    // Note: These two paths must only differ by the leading slash
    let servicePathNoSlash = "wstester"
    let servicePath = "/wstester"

    func performServerTest(line: Int = #line, asyncTasks: (XCTestExpectation) -> Void...) {
        let server = HTTP.createServer()
        server.allowPortReuse = true
        do {
            try server.listen(on: 8080)

            let requestQueue = DispatchQueue(label: "Request queue")

            for (index, asyncTask) in asyncTasks.enumerated() {
                let expectation = self.expectation(line: line, index: index)
                requestQueue.async {
                    asyncTask(expectation)
                }
            }

            waitForExpectations(timeout: 10) { error in
                // blocks test until request completes
                server.stop()
                XCTAssertNil(error)
            }
        } catch {
            XCTFail("Test failed. Error=\(error)")
        }
    }

    func createClient(negotiateCompression: Bool = false, uri: String = "/wstester" ,
                      contextTakeover: ContextTakeover = .both, requestKey: String = "test") -> WebSocketClient? {
        guard let client = WebSocketClient(host: "localhost", port: 8080, uri: uri, requestKey: requestKey,
                                           negotiateCompression: negotiateCompression ,contextTakeover: contextTakeover) else { return nil }
        do {
            try client.makeConnection()
        } catch let error {
            print("error \(error)")
        }
        return client
    }

    func expectation(line: Int, index: Int) -> XCTestExpectation {
        return self.expectation(description: "\(type(of: self)):\(line)[\(index)]")
    }

    func register(onPath: String? = nil, closeReason: WebSocketCloseReasonCode, testServerRequest: Bool = false, pingMessage: String? = nil, testQueryParams: Bool = false, connectionTimeout: Int? = nil) {
        let service = TestWebSocketService(closeReason: closeReason, testServerRequest: testServerRequest, pingMessage: pingMessage, testQueryParams: testQueryParams, connectionTimeout: connectionTimeout)
        WebSocket.register(service: service, onPath: onPath ?? servicePath)
    }
}

extension Bool {
    mutating func toggle() {
        self = !self
    }
}
