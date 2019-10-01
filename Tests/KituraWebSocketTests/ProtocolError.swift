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
import NIOWebSocket
import NIO
import LoggerAPI
@testable import KituraWebSocket

class ProtocolErrorTests: KituraTest {

    static var allTests: [(String, (ProtocolErrorTests) -> () throws -> Void)] {
        return [
            ("testBinaryAndTextFrames", testBinaryAndTextFrames),
            ("testPingWithOversizedPayload", testPingWithOversizedPayload),
            ("testFragmentedPing", testFragmentedPing),
            ("testInvalidOpCode", testInvalidOpCode),
            ("testUpgradeError", testUpgradeError),
            ("testInvalidUserCloseCode", testInvalidUserCloseCode),
            ("testCloseWithOversizedPayload", testCloseWithOversizedPayload),
            ("testJustContinuationFrame", testJustContinuationFrame),
            ("testJustFinalContinuationFrame", testJustFinalContinuationFrame),
            ("testInvalidUTF", testInvalidUTF),
            ("testInvalidUTFCloseMessage", testInvalidUTFCloseMessage),
            ("testTextAndBinaryFrames", testTextAndBinaryFrames),
            ("testUnmaskedFrame", testUnmaskedFrame),
            ("testInvalidRSVCode", testInvalidRSVCode)
        ]
    }

    func testBinaryAndTextFrames() {
        register(closeReason: .protocolError)
        performServerTest { expectation in
            let bytes:[UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
            let textPayload = "testing 1 2 3"

            guard let _client = self.createClient() else { return }
            _client.sendMessage(raw: bytes, opcode: .binary, finalFrame: false, compressed: false)
            _client.sendMessage(raw: textPayload, opcode: .text, finalFrame: true, compressed: false)
            _client.onClose {channel, data in
                var expectedPayload = ByteBufferAllocator().buffer(capacity: 8)
                expectedPayload.writeInteger(WebSocketCloseReasonCode.protocolError.code())
                expectedPayload.writeString("A text frame must be the first in the message")
                XCTAssertEqual(data, expectedPayload, "The payload \(data) doesn't equal the expected \(expectedPayload)")
                _ = channel.close()
                expectation.fulfill()
            }
        }
    }

    func testPingWithOversizedPayload() {
        register(closeReason: .protocolError)
        performServerTest { expectation in
            let oversizedPayload = [UInt8](repeating: 0x00, count: 126)
            guard let _client = self.createClient() else { return }
            _client.sendMessage(raw: oversizedPayload, opcode: .ping, finalFrame: true, compressed: false)
            _client.onClose {channel, data  in
                var expectedPayload = ByteBufferAllocator().buffer(capacity: 8)
                expectedPayload.writeInteger(WebSocketCloseReasonCode.protocolError.code())
                expectedPayload.writeString("Control frames are only allowed to have payload up to and including 125 octets")
                XCTAssertEqual(data, expectedPayload, "The payload \(data) doesn't equal the expected \(expectedPayload)")
                _ = channel.close()
                expectation.fulfill()
            }
        }
    }

    func testFragmentedPing() {
        register(closeReason: .protocolError)
        performServerTest { expectation in
            let text = "Testing, testing 1, 2, 3. "
            guard let _client = self.createClient() else { return }
            _client.sendMessage(raw: text, opcode: .ping, finalFrame: false, compressed: false)
            _client.sendMessage(raw: text, opcode: .continuation, finalFrame: false, compressed: false)
            _client.sendMessage(raw: text, opcode: .continuation, finalFrame: true, compressed: false)
            _client.onClose {channel, data in
                var expectedPayload = ByteBufferAllocator().buffer(capacity: 8)
                expectedPayload.writeInteger(WebSocketCloseReasonCode.protocolError.code())
                expectedPayload.writeString("Control frames must not be fragmented")
                XCTAssertEqual(data, expectedPayload, "The payload \(data) doesn't equal the expected \(expectedPayload)")
                _ = channel.close()
                expectation.fulfill()
            }
        }
    }

    func testInvalidOpCode() {
        register(closeReason: .protocolError)
        performServerTest { expectation in
            guard let _client = self.createClient() else { return }
            _client.sendMessage(raw: [0x00, 0x01], opcode: WebSocketOpcode(encodedWebSocketOpcode: 15)!, finalFrame: true)
            _client.onClose { channel, data in
                var expectedPayload = ByteBufferAllocator().buffer(capacity: 8)
                expectedPayload.writeInteger(WebSocketCloseReasonCode.protocolError.code())
                expectedPayload.writeString("Parsed a frame with an invalid operation code of 15")
                XCTAssertEqual(data, expectedPayload, "The payload \(data) doesn't equal the expected \(expectedPayload)")
                _ = channel.close()
                expectation.fulfill()
            }
        }
    }

    func testUpgradeError() {
        register(closeReason: .noReasonCodeSent)
        performServerTest { expectation in
            WebSocket.unregister(path: self.servicePath)
            guard let _client = WebSocketClient(host: "localhost", port: 8080, uri: "/wstester", requestKey: "test") else { return }
            _client.onError{ error,_  in
                print(error)
                expectation.fulfill()
            }
            try! _client.makeConnection()
        }
    }

    func testInvalidUserCloseCode() {
        register(closeReason: .protocolError)
        performServerTest { expectation in
            var closePayload = ByteBufferAllocator().buffer(capacity: 8)
                closePayload.writeInteger(WebSocketCloseReasonCode.userDefined(2999).code())
            guard let _client = self.createClient() else { return }
            _client.sendMessage(data: closePayload, opcode: .connectionClose, finalFrame: true)
            _client.onClose {channel, frame in
                var expectedPayload = ByteBufferAllocator().buffer(capacity: 8)
                expectedPayload.writeInteger(WebSocketCloseReasonCode.protocolError.code())
                XCTAssertEqual(frame, expectedPayload, "The payload \(frame) doesn't equal the expected \(expectedPayload)")
                _ = channel.close()
                expectation.fulfill()
            }
        }
    }

    func testCloseWithOversizedPayload() {
        register(closeReason: .protocolError)
        performServerTest { expectation in
            let oversizedPayload = [UInt8](repeating: 0x00, count: 126)
            guard let _client = self.createClient() else { return }
            _client.sendMessage(raw: oversizedPayload, opcode: .connectionClose, finalFrame: true)
            _client.onClose {channel, data in
                var expectedPayload = ByteBufferAllocator().buffer(capacity: 8)
                expectedPayload.writeInteger(WebSocketCloseReasonCode.protocolError.code())
                expectedPayload.writeString("Control frames are only allowed to have payload up to and including 125 octets")
                XCTAssertEqual(data, expectedPayload, "The payload \(data) doesn't equal the expected \(expectedPayload)")
                _ = channel.close()
                expectation.fulfill()
            }
        }
    }

    func testJustContinuationFrame() {
        register(closeReason: .protocolError)
        performServerTest { expectation in
            let bytes:[UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
            guard let _client = self.createClient() else { return }
            _client.sendMessage(raw: bytes, opcode: .continuation, finalFrame: true)
            _client.onClose {channel, data in
                var expectedPayload = ByteBufferAllocator().buffer(capacity: 8)
                expectedPayload.writeInteger(WebSocketCloseReasonCode.protocolError.code())
                expectedPayload.writeString("Continuation sent with prior binary or text frame")
                XCTAssertEqual(data, expectedPayload, "The payload \(data) doesn't equal the expected \(expectedPayload)")
                _ = channel.close()
                expectation.fulfill()
            }
        }
    }

    func testJustFinalContinuationFrame() {
        register(closeReason: .protocolError)
        performServerTest { expectation in
            let bytes:[UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
            guard let _client = self.createClient() else { return }
            _client.sendMessage(raw: bytes, opcode: .continuation, finalFrame: true)
            _client.onClose {channel, data in
                var expectedPayload = ByteBufferAllocator().buffer(capacity: 8)
                expectedPayload.writeInteger(WebSocketCloseReasonCode.protocolError.code())
                expectedPayload.writeString("Continuation sent with prior binary or text frame")
                XCTAssertEqual(data, expectedPayload, "The payload \(data) doesn't equal the expected \(expectedPayload)")
                _ = channel.close()
                expectation.fulfill()
            }
        }
    }

    func testInvalidUTF() {
        register(closeReason: .noReasonCodeSent)
        performServerTest { expectation in
            let testString = "Testing, 1,2,3"
            var payload = ByteBufferAllocator().buffer(capacity: 8)
            payload.writeInteger(WebSocketCloseReasonCode.normal.code())
            payload.writeBytes(testString.data(using: .utf16)!)
            guard let _client = self.createClient() else { return }
            _client.sendMessage(data: payload, opcode: .text, finalFrame: true)
            _client.onClose {channel, data in
                var expectedPayload = ByteBufferAllocator().buffer(capacity: 8)
                expectedPayload.writeInteger(WebSocketCloseReasonCode.invalidDataContents.code())
                expectedPayload.writeString("Failed to convert received payload to UTF-8 String")
                XCTAssertEqual(data, expectedPayload, "The payload \(data) doesn't equal the expected \(expectedPayload)")
                _ = channel.close()
                expectation.fulfill()
            }
        }
    }

    func testInvalidUTFCloseMessage() {
        register(closeReason: .noReasonCodeSent)
        performServerTest { expectation in
            let testString = "Testing, 1,2,3"
            var payload = ByteBufferAllocator().buffer(capacity: 8)
            payload.writeInteger(WebSocketCloseReasonCode.normal.code())
            payload.writeBytes(testString.data(using: String.Encoding.utf16)!)
            guard let _client = self.createClient() else { return }
            _client.sendMessage(data: payload, opcode: .connectionClose, finalFrame: true)
            _client.onClose { channel, data in
                var expectedPayload = ByteBufferAllocator().buffer(capacity: 8)
                expectedPayload.writeInteger(WebSocketCloseReasonCode.invalidDataContents.code())
                expectedPayload.writeString("Failed to convert received close message to UTF-8 String")
                XCTAssertEqual(data, expectedPayload, "The payload \(data) doesn't equal the expected \(expectedPayload)")
                _ = channel.close()
                expectation.fulfill()
            }
        }
    }

    func testTextAndBinaryFrames() {
        register(closeReason: .protocolError)
        performServerTest { expectation in
            let textPayload = "testing 1 2 3"
            let bytes:[UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
            guard let _client = self.createClient() else { return }
            _client.sendMessage(raw: textPayload, opcode: .text, finalFrame: false)
            _client.sendMessage(raw: bytes, opcode: .binary, finalFrame: true)
            _client.onClose {channel, data in
                var expectedPayload = ByteBufferAllocator().buffer(capacity: 8)
                expectedPayload.writeInteger(WebSocketCloseReasonCode.protocolError.code())
                expectedPayload.writeString("A binary frame must be the first in the message")
                XCTAssertEqual(data, expectedPayload, "The payload \(data) doesn't equal the expected \(expectedPayload)")
                _ = channel.close()
                expectation.fulfill()
            }
        }
    }

    func testUnmaskedFrame() {
        register(closeReason: .protocolError)

        performServerTest { expectation in
            guard let _client = self.createClient() else { return }
            _client.maskFrame = false
            _client.sendMessage(raw: [0x00, 0x01], opcode: .binary, finalFrame: true)
            _client.onClose { channel, data in
                var expectedPayload = ByteBufferAllocator().buffer(capacity: 8)
                expectedPayload.writeInteger(WebSocketCloseReasonCode.protocolError.code())
                expectedPayload.writeString("Received a frame from a client that wasn't masked")
                XCTAssertEqual(data, expectedPayload, "The payload \(data) doesn't equal the expected \(expectedPayload)")
                _ = channel.close()
                expectation.fulfill()
            }
        }
    }

    func testInvalidRSVCode() {
        register(closeReason: .protocolError)
        performServerTest (asyncTasks: { expectation in
            guard let _client = self.createClient() else { return }
            _client.sendMessage(raw: [0x00, 0x01], opcode: .binary, finalFrame: true, compressed: true)
            _client.onClose { channel, data in
                var expectedPayload = ByteBufferAllocator().buffer(capacity: 8)
                expectedPayload.writeInteger(WebSocketCloseReasonCode.protocolError.code())
                expectedPayload.writeString("RSV1 must be 0 unless negotiated to define meaning for non-zero values")
                XCTAssertEqual(data, expectedPayload, "The payload \(data) doesn't equal the expected   \(expectedPayload)")
                _ = channel.close()
                expectation.fulfill()
            }
        })
    }
}

