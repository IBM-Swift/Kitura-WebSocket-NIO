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
import Foundation
import Dispatch
import NIO
import NIOWebSocket
import NIOHTTP1

import LoggerAPI
@testable import KituraWebSocket
import Socket

class BasicTests: KituraTest {

    static var allTests: [(String, (BasicTests) -> () throws -> Void)] {
        return [
            ("testBinaryLongMessage", testBinaryLongMessage),
            ("testBinaryMediumMessage", testBinaryMediumMessage),
            ("testBinaryShortMessage", testBinaryShortMessage),
            ("testGracefullClose", testGracefullClose),
            ("testPing", testPing),
            ("testPingWithText", testPingWithText),
            ("testServerRequest", testServerRequest),
            ("testSuccessfulUpgrade", testSuccessfulUpgrade),
            ("testSuccessfulRemove", testSuccessfulRemove),
            ("testTextLongMessage", testTextLongMessage),
            ("testTextMediumMessage", testTextMediumMessage),
            ("testTextShortMessage", testTextShortMessage),
            ("testTextShortMessageWithQueryParams", testTextShortMessageWithQueryParams),
            ("testNullCharacter", testNullCharacter),
            ("testUserDefinedCloseCode", testUserDefinedCloseCode),
            ("testUserCloseMessage", testUserCloseMessage)
        ]
    }

    func testBinaryLongMessage() {
        register(closeReason: .noReasonCodeSent)
        var bytes: [UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
        repeat {
            bytes.append(contentsOf: bytes)
        } while bytes.count < 100000
        var payloadBuffer = ByteBufferAllocator().buffer(capacity: 16)
        payloadBuffer.writeBytes(bytes)
        performServerTest(asyncTasks: { expectation in
            guard let _client = self.createClient(requestKey: self.secWebKey) else { return }
            _client.sendMessage(bytes)
            _client.onMessage { receivedData in
                XCTAssertEqual(receivedData, payloadBuffer, "The payload \(receivedData) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
            }
        }, { expectation in
            guard let _client = self.createClient(negotiateCompression: true, requestKey: self.secWebKey) else { return }
            _client.sendMessage(raw: bytes, compressed: true)
            _client.onMessage { receivedData in
                XCTAssertEqual(receivedData, payloadBuffer, "The payload \(receivedData) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
            }
        }, { expectation in
            guard let _client = self.createClient(negotiateCompression: true, requestKey: self.secWebKey) else { return }
            _client.sendMessage(bytes)
            _client.onMessage { receivedData in
                XCTAssertEqual(receivedData, payloadBuffer, "The payload \(receivedData) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
            }
        })
    }

    func testBinaryMediumMessage() {
        register(closeReason: .noReasonCodeSent)
        var bytes: [UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
        repeat {
            bytes.append(contentsOf: bytes)
        } while bytes.count < 1000
        var payloadBuffer = ByteBufferAllocator().buffer(capacity: 16)
        payloadBuffer.writeBytes(bytes)

        performServerTest(asyncTasks: { expectation in
            guard let _client = self.createClient(requestKey: self.secWebKey) else { return }
            _client.sendMessage(bytes)
            _client.onMessage { receivedData in
                XCTAssertEqual(receivedData, payloadBuffer, "The payload \(receivedData) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
            }
        }, { expectation in
            guard let _client = self.createClient(negotiateCompression: true, requestKey: self.secWebKey) else { return }
            _client.sendMessage(raw: bytes, compressed: true)
            _client.onMessage { receivedData in
                XCTAssertEqual(receivedData, payloadBuffer, "The payload \(receivedData) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
            }
        }, { expectation in
            guard let _client = self.createClient(negotiateCompression: true, requestKey:self.secWebKey) else { return }
            _client.sendMessage(bytes)
            _client.onMessage { receivedData in
                XCTAssertEqual(receivedData, payloadBuffer, "The payload \(receivedData) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
            }
        })
    }

    func testBinaryShortMessage() {
        register(closeReason: .noReasonCodeSent)
        let bytes: [UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
        var payloadBuffer = ByteBufferAllocator().buffer(capacity: 16)
        payloadBuffer.writeBytes(bytes)

        performServerTest(asyncTasks: { expectation in
            guard let _client = self.createClient(requestKey: self.secWebKey) else { return }
            _client.sendMessage(bytes)
            _client.onMessage { receivedData in
                XCTAssertEqual(receivedData, payloadBuffer, "The payload \(receivedData) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
            }
        }, {expectation in
            guard let _client = self.createClient(negotiateCompression: true, requestKey: self.secWebKey) else { return }
            _client.sendMessage(raw: bytes, compressed: true)
            _client.onMessage { receivedData in
                XCTAssertEqual(receivedData, payloadBuffer, "The payload \(receivedData) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
            }
        }, { expectation in
            guard let _client = self.createClient(negotiateCompression: true, requestKey: self.secWebKey) else { return }
            _client.sendMessage(bytes)
            _client.onMessage { receivedData in
                XCTAssertEqual(receivedData, payloadBuffer, "The payload \(receivedData) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
            }
        })
    }

    func testGracefullClose() {
        register(closeReason: .normal)
        performServerTest { expectation in
            var payloadBuffer = ByteBufferAllocator().buffer(capacity: 8)
            payloadBuffer.writeInteger(WebSocketCloseReasonCode.normal.code())
            guard let _client = self.createClient(requestKey: self.secWebKey) else { return }
            _client.sendMessage(data: payloadBuffer, opcode: .connectionClose, finalFrame: true, compressed: false)
            _client.onClose { channel, _ in
                _ = channel.close()
                expectation.fulfill()
            }
        }
    }

    func testPing() {
        register(closeReason: .noReasonCodeSent)
        performServerTest { expectation in
            guard let _client = self.createClient(negotiateCompression: true, requestKey: self.secWebKey) else { return }
            _client.ping()
            _client.onPong { code, _ in
                XCTAssertEqual(code, WebSocketOpcode.pong, "Recieved opcode \(code) doesn't equal expected \(WebSocketOpcode.pong)")
                expectation.fulfill()
            }
        }
    }

    func testPingWithText() {
        register(closeReason: .noReasonCodeSent)
        performServerTest { expectation in
            var payloadBuffer = ByteBufferAllocator().buffer(capacity: 8)
            payloadBuffer.writeString("Testing, testing 1,2,3")
            guard let _client = self.createClient(requestKey: self.secWebKey) else { return }
            _client.sendMessage(data: payloadBuffer, opcode: .ping, finalFrame: true, compressed: false)
            _client.onPong { code, data in
                XCTAssertEqual(code, WebSocketOpcode.pong, "Recieved opcode \(code) doesn't equal expected \(WebSocketOpcode.pong)")
                XCTAssertEqual(data, payloadBuffer, "The payload \(data) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
            }
        }
    }

    func testServerRequest() {
        register(closeReason: .noReasonCodeSent, testServerRequest: true)

        performServerTest { expectation in
            guard self.createClient() != nil else { return }

            sleep(3)       // Wait a bit for the WebSocketService to test the ServerRequest

            expectation.fulfill()
        }
    }

    func testSuccessfulRemove() {
        register(closeReason: .noReasonCodeSent)
        performServerTest { expectation in
            guard let _client1 = self.createClient() else { return }
            XCTAssertTrue(_client1.isConnected, "Client not connected")
            WebSocket.unregister(path: self.servicePath)
            guard let _client2 = WebSocketClient(host: "localhost", port: 8080, uri: self.servicePath, requestKey: "test") else { return }
            _client2.onError { _, status in
                XCTAssertEqual(status, HTTPResponseStatus.badRequest,
                               "Status \(String(describing: status)) returned from server is not equal to \(HTTPResponseStatus.badRequest)" )
                expectation.fulfill()
            }
            _client2.makeConnection()
        }
    }

    func testSuccessfulUpgrade() {
        register(closeReason: .noReasonCodeSent) //with NIOWebSocket, the Websocket handler cannot be added to a listening server
        performServerTest(asyncTasks: { expectation in
            WebSocket.unregister(path: self.servicePathNoSlash)
            self.register(onPath: self.servicePathNoSlash, closeReason: .noReasonCodeSent)
            guard let _client = self.createClient(uri: self.servicePath) else { return }
            XCTAssertTrue(_client.isConnected, "WebSocket Upgrade failed")
            expectation.fulfill()
        }, { expectation in
            WebSocket.unregister(path: self.servicePath)
            self.register(onPath: self.servicePath, closeReason: .noReasonCodeSent)
            guard let _client = self.createClient(uri: self.servicePath) else { return }
            XCTAssertTrue(_client.isConnected, "WebSocket Upgrade failed")
            expectation.fulfill()
        })
    }

    func testTextLongMessage() {
        register(closeReason: .noReasonCodeSent)
        var text = "Testing, testing 1, 2, 3."
        repeat {
            text += " " + text
        } while text.count < 100000
        var payloadBuffer = ByteBufferAllocator().buffer(capacity: text.count)
        payloadBuffer.writeString(text)
        performServerTest(asyncTasks: { expectation in
            guard let _client = self.createClient() else { return }
            _client.sendMessage(text)
            _client.onMessage { receivedData in
                XCTAssertEqual(receivedData, payloadBuffer, "The payload \(receivedData) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
            }
        }, { expectation in
            guard let _client = self.createClient(negotiateCompression: true) else { return }
            _client.sendMessage(raw: text, compressed: true)
            _client.onMessage { receivedData in
                XCTAssertEqual(receivedData, payloadBuffer, "The payload \(receivedData) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
            }
        }, { expectation in
            guard let _client = self.createClient(negotiateCompression: true) else { return }
            _client.sendMessage(text)
            _client.onMessage { receivedData in
                XCTAssertEqual(receivedData, payloadBuffer, "The payload \(receivedData) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
            }
        })
    }

    func testTextMediumMessage() {
        register(closeReason: .noReasonCodeSent)
        var text = ""
        repeat {
            text += "Testing, testing 1,2,3. "
        } while text.count < 1000
        var payloadBuffer = ByteBufferAllocator().buffer(capacity: text.count)
        payloadBuffer.writeString(text)
        performServerTest(asyncTasks: { expectation in
            guard let _client = self.createClient() else { return }
            _client.sendMessage(text)
            _client.onMessage { receivedData in
                XCTAssertEqual(receivedData, payloadBuffer, "The payload \(receivedData) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
            }
        }, { expectation in
            guard let _client = self.createClient(negotiateCompression: true) else { return }
            _client.sendMessage(raw: text, compressed: true)
            _client.onMessage { receivedData in
                XCTAssertEqual(receivedData, payloadBuffer, "The payload \(receivedData) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
            }
        }, { expectation in
            guard let _client = self.createClient(negotiateCompression: true) else { return }
            _client.sendMessage(text)
            _client.onMessage { receivedData in
                XCTAssertEqual(receivedData, payloadBuffer, "The payload \(receivedData) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
            }
        })
    }

    func testTextShortMessage() {
         register(closeReason: .noReasonCodeSent)
        let textPayload = "Testing, testing 1,2,3"
        var payloadBuffer = ByteBufferAllocator().buffer(capacity: textPayload.count)
        payloadBuffer.writeString(textPayload)
        performServerTest(asyncTasks: { expectation in
            guard let _client = self.createClient() else { return }
            _client.sendMessage(textPayload)
            _client.onMessage { receivedData in
                XCTAssertEqual(receivedData, payloadBuffer, "The payload \(receivedData) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
            }
        }, { expectation in
            guard let _client = self.createClient(negotiateCompression: true) else { return }
            _client.sendMessage(raw: textPayload, compressed: true)
            _client.onMessage { receivedData in
                XCTAssertEqual(receivedData, payloadBuffer, "The payload \(receivedData) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
        }
        }, { expectation in
            guard let _client = self.createClient(negotiateCompression: true) else { return }
            _client.sendMessage(textPayload)
            _client.onMessage { receivedData in
                XCTAssertEqual(receivedData, payloadBuffer, "The payload \(receivedData) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
            }
        })
    }

    func testTextShortMessageWithQueryParams() {
        register(closeReason: .noReasonCodeSent, testQueryParams: true)
        performServerTest(asyncTasks: { expectation in
            let textPayload = "Keys and Values: "
            guard let _client = self.createClient(uri: "/wstester?p1=v1&p2=v2") else { return }
            _client.sendMessage(textPayload)
            _client.onMessage { recieved in
                var expectedPayload = ByteBufferAllocator().buffer(capacity: 8)
                expectedPayload.writeString("Keys and Values: p1,p2 and v1,v2")
                XCTAssertEqual(recieved, expectedPayload, "The payload \(recieved) doesn't equal \(expectedPayload)")
                expectation.fulfill()
            }
        })
    }

    func testUserDefinedCloseCode() {
        register(closeReason: .userDefined(65535))
        performServerTest { expectation in
            var closePayload = ByteBufferAllocator().buffer(capacity: 8)
            closePayload.writeInteger(WebSocketCloseReasonCode.userDefined(65535).code())
            guard let _client = self.createClient() else { return }
            _client.sendMessage(data: closePayload, opcode: .connectionClose, finalFrame: true, compressed: false)
            _client.onClose { _, data in
                XCTAssertEqual(data, closePayload, "The payload \(data) doesn't equal \(closePayload)")
                expectation.fulfill()
            }
        }
    }

    func testUserCloseMessage() {
        register(closeReason: .normal)
        performServerTest { expectation in
            let testString = "Testing, 1,2,3"
            var payloadBuffer = ByteBufferAllocator().buffer(capacity: 16)
            payloadBuffer.writeInteger(WebSocketCloseReasonCode.normal.code())
            payloadBuffer.writeString(testString)
            guard let _client = self.createClient() else { return }
            _client.sendMessage(data: payloadBuffer, opcode: .connectionClose, finalFrame: true, compressed: false)
            _client.onClose { _, data in
                XCTAssertEqual(data, payloadBuffer, "The payload \(data) doesn't equal the expected \(payloadBuffer)")
                expectation.fulfill()
            }
        }
    }

    func testNullCharacter() {
        register(closeReason: .noReasonCodeSent)
        performServerTest { expectation in
            guard let _client = self.createClient() else { return }
            _client.sendMessage("\u{00}")
            _client.onMessage { data in
                XCTAssertEqual(data.getString(at: 0, length: data.readableBytes), "\u{00}", "The Payload doesn't Equal expected payload ")
                expectation.fulfill()
            }
        }
    }
}
