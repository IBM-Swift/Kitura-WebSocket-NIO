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
import LoggerAPI
@testable import KituraWebSocket

class ComplexTests: KituraTest {

    static var allTests: [(String, (ComplexTests) -> () throws -> Void)] {
        return [
            ("testBinaryShortAndMediumFrames", testBinaryShortAndMediumFrames),
            ("testBinaryTwoShortFrames", testBinaryTwoShortFrames),
            ("testPingBetweenBinaryFrames", testPingBetweenBinaryFrames),
            ("testPingBetweenTextFrames", testPingBetweenTextFrames),
            ("testTextShortAndMediumFrames", testTextShortAndMediumFrames),
            ("testTextTwoShortFrames", testTextTwoShortFrames),
            ("testTwoMessagesWithContextTakeover", testTwoMessagesWithContextTakeover),
            ("testTwoMessagesWithClientContextTakeover", testTwoMessagesWithClientContextTakeover),
            ("testTwoMessagesWithServerContextTakeover", testTwoMessagesWithServerContextTakeover),
            ("testTwoMessagesWithNoContextTakeover", testTwoMessagesWithNoContextTakeover)
        ]
    }

    func testBinaryShortAndMediumFrames() {
        register(closeReason: .noReasonCodeSent)

        let bytes: [UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
        var mediumBinaryPayload = bytes
        repeat {
            mediumBinaryPayload.append(contentsOf: mediumBinaryPayload)
        } while mediumBinaryPayload.count < 1000

        var expectedFrame = bytes
        expectedFrame.append(contentsOf: mediumBinaryPayload)
        performServerTest(asyncTasks: { expectation in
            guard let _client = self.createClient() else { return }
            _client.sendMessage(raw: bytes, opcode: .binary, finalFrame: false, compressed: false)
            _client.sendMessage(raw: mediumBinaryPayload, opcode: .continuation, finalFrame: true, compressed: false)
            _client.onMessage { receivedData in
                let payload = receivedData.getBytes(at: 0, length: receivedData.readableBytes)!
                XCTAssertEqual(payload, expectedFrame, "The payload recieved \(payload) is not equal to expected payload \(expectedFrame).")
                expectation.fulfill()
            }
        }, { expectation in
            guard let _client = self.createClient(negotiateCompression: true) else { return }
            _client.sendMessage(raw: bytes, opcode: .binary, finalFrame: false, compressed: true)
            _client.sendMessage(raw: mediumBinaryPayload, opcode: .continuation, finalFrame: true, compressed: true)
            _client.onMessage { receivedData in
                let payload = receivedData.getBytes(at: 0, length: receivedData.readableBytes)!
                XCTAssertEqual(payload, expectedFrame, "The payload recieved \(payload) is not equal to expected payload \(expectedFrame).")
                expectation.fulfill()
            }
        }, { expectation in
            guard let _client = self.createClient(negotiateCompression: true) else { return }
            _client.sendMessage(raw: bytes, opcode: .binary, finalFrame: false, compressed: false)
            _client.sendMessage(raw: mediumBinaryPayload, opcode: .continuation, finalFrame: true, compressed: false)
            _client.onMessage { receivedData in
                let payload = receivedData.getBytes(at: 0, length: receivedData.readableBytes)!
                XCTAssertEqual(payload, expectedFrame, "The payload recieved \(payload) is not equal to expected payload \(expectedFrame).")
                expectation.fulfill()
            }
        })
    }

    func testBinaryTwoShortFrames() {
        register(closeReason: .noReasonCodeSent)

        let bytes: [UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
        var expectedBinaryPayload = bytes
        expectedBinaryPayload.append(contentsOf: bytes)

        performServerTest(asyncTasks: { expectation in
            guard let _client = self.createClient() else { return }
            _client.sendMessage(raw: bytes, opcode: .binary, finalFrame: false)
            _client.sendMessage(raw: bytes, opcode: .continuation, finalFrame: true)
            _client.onMessage { receivedData in
                let payload = receivedData.getBytes(at: 0, length: receivedData.readableBytes)!
                XCTAssertEqual(payload, expectedBinaryPayload, "The payload recieved \(payload) is not equal to expected payload \(expectedBinaryPayload).")
                expectation.fulfill()
            }
        }, {expectation in
            guard let _client = self.createClient(negotiateCompression: true) else { return }
            _client.sendMessage(raw: bytes, opcode: .binary, finalFrame: false, compressed: true)
            _client.sendMessage(raw: bytes, opcode: .continuation, finalFrame: true, compressed: true)
            _client.onMessage { receivedData in
                let payload = receivedData.getBytes(at: 0, length: receivedData.readableBytes)!
                XCTAssertEqual(payload, expectedBinaryPayload, "The payload recieved \(payload) is not equal to expected payload \(expectedBinaryPayload).")
                expectation.fulfill()
            }
        }, { expectation in
            guard let _client = self.createClient(negotiateCompression: true) else { return }
            _client.sendMessage(raw: bytes, opcode: .binary, finalFrame: false, compressed: false)
            _client.sendMessage(raw: bytes, opcode: .continuation, finalFrame: true, compressed: false)
            _client.onMessage { receivedData in
                let payload = receivedData.getBytes(at: 0, length: receivedData.readableBytes)!
                XCTAssertEqual(payload, expectedBinaryPayload, "The payload recieved \(payload) is not equal to expected payload \(expectedBinaryPayload).")
                expectation.fulfill()
            }
        })
    }

    func testPingBetweenBinaryFrames() {
        register(closeReason: .noReasonCodeSent)
        performServerTest { expectation in
            let bytes: [UInt8] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
            var expectedBinaryPayload = bytes
            expectedBinaryPayload.append(contentsOf: bytes)
            let pingPayload = "Testing, testing 1,2,3"
            guard let _client = self.createClient() else { return }
            _client.sendMessage(raw: bytes, opcode: .binary, finalFrame: false)
            _client.sendMessage(raw: pingPayload, opcode: .ping, finalFrame: true)
            _client.sendMessage(raw: bytes, opcode: .continuation, finalFrame: true)
            _client.onMessage { receivedData in
                let payload = receivedData.getBytes(at: 0, length: receivedData.readableBytes)!
                XCTAssertEqual(payload, expectedBinaryPayload, "The payload recieved \(payload) is not equal to expected payload \(expectedBinaryPayload).")
                expectation.fulfill()
            }
            _client.onPong { opcode, _ in
                XCTAssertEqual(opcode, WebSocketOpcode.pong, "Recieved opcode \(opcode) is not equal expected opcode \(WebSocketOpcode.pong).")
            }

        }

    }

    func testPingBetweenTextFrames() {
        register(closeReason: .noReasonCodeSent)
        performServerTest { expectation in
            let text = "Testing, testing 1, 2, 3. "
            let pingPayload = "Testing, testing 1,2,3"
            var expectedPayload = text
            expectedPayload.append(contentsOf: text)

            guard let _client = self.createClient() else { return }
            _client.sendMessage(raw: text, opcode: .text, finalFrame: false)
            _client.sendMessage(raw: pingPayload, opcode: .ping, finalFrame: true)
            _client.sendMessage(raw: text, opcode: .continuation, finalFrame: true)
            _client.onMessage { receivedData in
                let payload = receivedData.getString(at: 0, length: receivedData.readableBytes)
                XCTAssertEqual(payload, expectedPayload, "The payload recieved \(String(describing: payload)) is not equal to expected payload \(expectedPayload).")
                expectation.fulfill()
            }
            _client.onPong { opcode, _ in
                XCTAssertEqual(opcode, WebSocketOpcode.pong, "Recieved opcode \(opcode) is not equal expected opcode \(WebSocketOpcode.pong)")
            }
        }

    }

    func testTextShortAndMediumFrames() {
        register(closeReason: .noReasonCodeSent)

        let shortText = "Testing, testing 1, 2, 3. "
        var mediumText = ""
        repeat {
            mediumText += "Testing, testing 1,2,3. "
        } while mediumText.count < 1000
        var textExpectedPayload = shortText
        textExpectedPayload.append(contentsOf: mediumText)
        performServerTest(asyncTasks: { expectation in
            guard let _client = self.createClient() else { return }
            _client.sendMessage(raw: shortText, opcode: .text, finalFrame: false)
            _client.sendMessage(raw: mediumText, opcode: .continuation, finalFrame: true)
            _client.onMessage { receivedData in
                let payload = receivedData.getString(at: 0, length: receivedData.readableBytes)!
                XCTAssertEqual(payload, textExpectedPayload, "The payload recieved \(String(describing: payload)) is not equal to expected payload \(textExpectedPayload).")
                expectation.fulfill()
            }
        }, { expectation in
            guard let _client = self.createClient(negotiateCompression: true) else { return }
            _client.sendMessage(raw: shortText, opcode: .text, finalFrame: false, compressed: true)
            _client.sendMessage(raw: mediumText, opcode: .continuation, finalFrame: true, compressed: true)
            _client.onMessage { receivedData in
                let payload = receivedData.getString(at: 0, length: receivedData.readableBytes)!
                XCTAssertEqual(payload, textExpectedPayload, "The payload recieved \(String(describing: payload)) is not equal to expected payload \(textExpectedPayload).")
                expectation.fulfill()
            }
        }, { expectation in
            guard let _client = self.createClient(negotiateCompression: true) else { return }
            _client.sendMessage(raw: shortText, opcode: .text, finalFrame: false)
            _client.sendMessage(raw: mediumText, opcode: .continuation, finalFrame: true)
            _client.onMessage { receivedData in
                let payload = receivedData.getString(at: 0, length: receivedData.readableBytes)!
                XCTAssertEqual(payload, textExpectedPayload, "The payload recieved \(String(describing: payload)) is not equal to expected payload \(textExpectedPayload).")
                expectation.fulfill()
            }
        })
    }

    func testTextTwoShortFrames() {
        register(closeReason: .noReasonCodeSent)

        let text = "Testing, testing 1, 2, 3. "
        var textExpectedPayload = text
        textExpectedPayload.append(contentsOf: text)
        performServerTest(asyncTasks: { expectation in
            guard let _client = self.createClient(negotiateCompression: true) else { return }
            _client.sendMessage(raw: text, opcode: .text, finalFrame: false)
            _client.sendMessage(raw: text, opcode: .continuation, finalFrame: true)
            _client.onMessage { receivedData in
                let payload = receivedData.getString(at: 0, length: receivedData.readableBytes)!
                XCTAssertEqual(payload, textExpectedPayload, "The payload recieved \(String(describing: payload)) is not equal to expected payload \(textExpectedPayload).")
                expectation.fulfill()
            }
        }, { expectation in
            guard let _client = self.createClient(negotiateCompression: true) else { return }
            _client.sendMessage(raw: text, opcode: .text, finalFrame: false, compressed: true)
            _client.sendMessage(raw: text, opcode: .continuation, finalFrame: true, compressed: true)
            _client.onMessage { receivedData in
                let payload = receivedData.getString(at: 0, length: receivedData.readableBytes)!
                XCTAssertEqual(payload, textExpectedPayload, "The payload recieved \(String(describing: payload)) is not equal to expected payload \(textExpectedPayload).")
                expectation.fulfill()
            }
        }, { expectation in
            guard let _client = self.createClient(negotiateCompression: true) else { return }
            _client.sendMessage(raw: text, opcode: .text, finalFrame: false)
            _client.sendMessage(raw: text, opcode: .continuation, finalFrame: true)
            _client.onMessage { receivedData in
                let payload = receivedData.getString(at: 0, length: receivedData.readableBytes)!
                XCTAssertEqual(payload, textExpectedPayload, "The payload recieved \(String(describing: payload)) is not equal to expected payload \(textExpectedPayload).")
                expectation.fulfill()
            }
        })
    }

    func testTwoMessages(contextTakeover: ContextTakeover = .both) {
        register(closeReason: .noReasonCodeSent)

        let text = "RFC7692 specifies a framework for adding compression functionality to the WebSocket Protocol"
        performServerTest { expectation in
            var count = 0
            guard let _client = self.createClient(negotiateCompression: true, contextTakeover: contextTakeover) else { return }
            _client.sendMessage(raw: text, opcode: .text, finalFrame: true)
            _client.sendMessage(raw: text, opcode: .text, finalFrame: true)
            _client.onMessage { receivedData in
                count += 1
                let payload = receivedData.getString(at: 0, length: receivedData.readableBytes)!
                XCTAssertEqual(payload, text, "The payload recieved \(String(describing: payload)) is not equal to expected payload \(text).")
                if count == 2 {
                    expectation.fulfill()
                }
            }
        }
    }

    func testTwoMessagesWithContextTakeover() {
        testTwoMessages(contextTakeover: .both)
    }

    func testTwoMessagesWithClientContextTakeover() {
        testTwoMessages(contextTakeover: .client)
    }

    func testTwoMessagesWithServerContextTakeover() {
        testTwoMessages(contextTakeover: .server)
    }

    func testTwoMessagesWithNoContextTakeover() {
        testTwoMessages(contextTakeover: .none)
    }
}
