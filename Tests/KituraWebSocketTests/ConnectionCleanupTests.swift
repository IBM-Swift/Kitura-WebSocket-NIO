/*
 * Copyright IBM Corporation 2019
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
 */
import XCTest
import Foundation

import NIO
import NIOWebSocket

class ConnectionCleanupTests: KituraTest {

    static var allTests: [(String, (ConnectionCleanupTests) -> () throws -> Void)] {
        return [
            ("testNilConnectionTimeOut", testNilConnectionTimeOut),
            ("testSingleConnectionTimeOut", testSingleConnectionTimeOut),
            ("testPingKeepsConnectionAlive", testPingKeepsConnectionAlive),
            ("testMultiConnectionTimeOut", testMultiConnectionTimeOut)
        ]
    }

    func testNilConnectionTimeOut() {
        register(closeReason: .noReasonCodeSent)
        performServerTest { expectation in
            let _client = WebSocketClient(host: "localhost", port: 8080,
                                         uri: "/wstester", requestKey: "test")
            guard let client = _client else {
                XCTFail("Couldn't create a WebSocket connection")
                return
            }
            sleep(2)
            XCTAssertTrue(client.isConnected)
            expectation.fulfill()
        }
    }

    func testSingleConnectionTimeOut() {
        register(closeReason: .noReasonCodeSent, connectionTimeout: 2)
        performServerTest { expectation in
            let _client = WebSocketClient(host: "localhost", port: 8080,
                                         uri: "/wstester", requestKey: "test")
            guard let client = _client else {
                XCTFail("Couldn't create a WebSocket connection")
                return
            }
            sleep(4)
            XCTAssertFalse(client.isConnected)
            expectation.fulfill()
        }
    }

    func testPingKeepsConnectionAlive() {
        register(closeReason: .noReasonCodeSent, connectionTimeout: 2)
        performServerTest { expectation in
            let _client = WebSocketClient(host: "localhost", port: 8080,
                                         uri: "/wstester", requestKey: "test")
            guard let client = _client else {
                XCTFail("Couldn't create a WebSocket connection")
                return
            }

            client.onPing { data in
                client.pong(data: data)
            }

            sleep(4)
            XCTAssertTrue(client.isConnected)
            expectation.fulfill()
        }
    }

    func testMultiConnectionTimeOut() {
        register(closeReason: .noReasonCodeSent, connectionTimeout: 2)

        performServerTest { expectation in
            let _client1 = WebSocketClient(host: "localhost",
                                          port: 8080,
                                          uri: "/wstester",
                                          requestKey: "test")
            guard let client1 = _client1 else {
                XCTFail("Couldn't establish a WebSocket connection with the server")
                return
            }

            let _client2 = WebSocketClient(host: "localhost",
                                                port: 8080,
                                                uri: "/wstester",
                                                requestKey: "test")
            guard let client2 = _client2 else {
                XCTFail("Couldn't create a WebSocket connection")
                return
            }

            client2.onPing { data in
                client2.pong(data: data)
            }

            sleep(4)
            XCTAssertFalse(client1.isConnected)
            XCTAssertTrue(client2.isConnected)
            expectation.fulfill()
        }
    }
}

