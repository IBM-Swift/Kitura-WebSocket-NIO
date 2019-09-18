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
            guard let client = self.createClient() else { return }
            sleep(2)
            XCTAssertTrue(client.isConnected)
            expectation.fulfill()
        }
    }

    func testSingleConnectionTimeOut() {
        register(closeReason: .noReasonCodeSent, connectionTimeout: 2)
        performServerTest { expectation in
            guard let client = self.createClient() else { return }
            sleep(4)
            XCTAssertFalse(client.isConnected)
            expectation.fulfill()
        }
    }

    func testPingKeepsConnectionAlive() {
        register(closeReason: .noReasonCodeSent, connectionTimeout: 2)
        performServerTest { expectation in
            guard let client = self.createClient() else { return }
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
            guard let client1 = self.createClient() else { return }
            guard let client2 = self.createClient() else { return }

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

