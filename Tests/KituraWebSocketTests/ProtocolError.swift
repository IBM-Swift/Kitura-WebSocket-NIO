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

import LoggerAPI
@testable import KituraWebSocket

class ProtocolErrorTests: KituraTest {

    static var allTests: [(String, (ProtocolErrorTests) -> () throws -> Void)] {
        return [
            ("testBinaryAndTextFrames", testBinaryAndTextFrames),
            ("testPingWithOversizedPayload", testPingWithOversizedPayload),
            ("testFragmentedPing", testFragmentedPing),
            ("testInvalidOpCode", testInvalidOpCode),
            ("testInvalidUserCloseCode", testInvalidUserCloseCode),
            ("testCloseWithOversizedPayload", testCloseWithOversizedPayload),
            ("testJustContinuationFrame", testJustContinuationFrame),
            ("testJustFinalContinuationFrame", testJustFinalContinuationFrame),
            ("testInvalidUTF", testInvalidUTF),
            ("testInvalidUTFCloseMessage", testInvalidUTFCloseMessage),
            ("testTextAndBinaryFrames", testTextAndBinaryFrames),
            ("testUnmaskedFrame", testUnmaskedFrame)
        ]
    }

    func testBinaryAndTextFrames() {
        register(closeReason: .protocolError)

        performServerTest { expectation in

            var bytes = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]

            let binaryPayload = NSMutableData(bytes: &bytes, length: bytes.count)

            let textPayload = self.payload(text: "testing 1 2 3")

            let expectedPayload = NSMutableData()
            var part = self.payload(closeReasonCode: .protocolError)
            expectedPayload.append(part.bytes, length: part.length)
            part = self.payload(text: "A text frame must be the first in the message")
            expectedPayload.append(part.bytes, length: part.length)

            self.performTest(framesToSend: [(false, self.opcodeBinary, binaryPayload),
                                            (true, self.opcodeText, textPayload)],
                             expectedFrames: [(true, self.opcodeClose, expectedPayload)],
                             expectation: expectation)
        }
    }

    func testPingWithOversizedPayload() {
        register(closeReason: .protocolError)

        let expectedPayload = NSMutableData()
        var part = self.payload(closeReasonCode: .protocolError)
        expectedPayload.append(part.bytes, length: part.length)
        part = self.payload(text: "Control frames are only allowed to have payload up to and including 125 octets")
        expectedPayload.append(part.bytes, length: part.length)

        performServerTest { expectation in
            let oversizedPayload = NSMutableData()
            oversizedPayload.append(Data(repeatElement(0, count: 126)))
            self.performTest(framesToSend: [(true, self.opcodePing, oversizedPayload)],
                             expectedFrames: [(true, self.opcodeClose, expectedPayload)],
                             expectation: expectation)
        }
    }

    func testFragmentedPing() {
        register(closeReason: .protocolError)

        performServerTest { expectation in

            let text = "Testing, testing 1, 2, 3. "

            let textPayload = self.payload(text: text)

            let expectedPayload = NSMutableData()
            var part = self.payload(closeReasonCode: .protocolError)
            expectedPayload.append(part.bytes, length: part.length)
            part = self.payload(text: "Control frames must not be fragmented")
            expectedPayload.append(part.bytes, length: part.length)

            let pingPayload = self.payload(text: "Testing, testing 1,2,3")

            self.performTest(framesToSend: [(false, self.opcodePing, pingPayload),
                                            (false, self.opcodeContinuation, textPayload),
                                            (true, self.opcodeContinuation, textPayload)],
                             expectedFrames: [(true, self.opcodeClose, expectedPayload)],
                             expectation: expectation)
        }
    }

    func testInvalidOpCode() {
        register(closeReason: .protocolError)

        performServerTest { expectation in

            var bytes = [0x00, 0x01]
            let payload = NSMutableData(bytes: &bytes, length: bytes.count)

            let expectedPayload = NSMutableData()
            var part = self.payload(closeReasonCode: .protocolError)
            expectedPayload.append(part.bytes, length: part.length)
            part = self.payload(text: "Parsed a frame with an invalid operation code of 15")
            expectedPayload.append(part.bytes, length: part.length)

            self.performTest(framesToSend: [(true, 15, payload)],
                             expectedFrames: [(true, self.opcodeClose, expectedPayload)],
                             expectation: expectation)
        }
    }

    func testInvalidUserCloseCode() {
        register(closeReason: .protocolError)

        performServerTest { expectation in

            let closePayload = self.payload(closeReasonCode: .userDefined(2999))
            let returnPayload = self.payload(closeReasonCode: .protocolError)
            self.performTest(framesToSend: [(true, self.opcodeClose, closePayload)],
                             expectedFrames: [(true, self.opcodeClose, returnPayload)],
                             expectation: expectation)
        }
    }

    func testCloseWithOversizedPayload() {
        register(closeReason: .protocolError)

        let expectedPayload = NSMutableData()
        var part = self.payload(closeReasonCode: .protocolError)
        expectedPayload.append(part.bytes, length: part.length)
        part = self.payload(text: "Control frames are only allowed to have payload up to and including 125 octets")
        expectedPayload.append(part.bytes, length: part.length)

        performServerTest { expectation in
            let oversizedPayload = NSMutableData()
            oversizedPayload.append(Data(repeatElement(0, count: 126)))
            self.performTest(framesToSend: [(true, self.opcodeClose, oversizedPayload)],
                             expectedFrames: [(true, self.opcodeClose, expectedPayload)],
                             expectation: expectation)
        }
    }

    func testJustContinuationFrame() {
        register(closeReason: .protocolError)

        performServerTest { expectation in

            var bytes = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]

            let payload = NSMutableData(bytes: &bytes, length: bytes.count)

            let expectedPayload = NSMutableData()
            var part = self.payload(closeReasonCode: .protocolError)
            expectedPayload.append(part.bytes, length: part.length)
            part = self.payload(text: "Continuation sent with prior binary or text frame")
            expectedPayload.append(part.bytes, length: part.length)

            self.performTest(framesToSend: [(false, self.opcodeContinuation, payload)],
                             expectedFrames: [(true, self.opcodeClose, expectedPayload)],
                             expectation: expectation)
        }
    }

    func testJustFinalContinuationFrame() {
        register(closeReason: .protocolError)

        performServerTest { expectation in

            var bytes = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]

            let payload = NSMutableData(bytes: &bytes, length: bytes.count)

            let expectedPayload = NSMutableData()
            var part = self.payload(closeReasonCode: .protocolError)
            expectedPayload.append(part.bytes, length: part.length)
            part = self.payload(text: "Continuation sent with prior binary or text frame")
            expectedPayload.append(part.bytes, length: part.length)

            self.performTest(framesToSend: [(true, self.opcodeContinuation, payload)],
                             expectedFrames: [(true, self.opcodeClose, expectedPayload)],
                             expectation: expectation)
        }
    }

    func testInvalidUTF() {
        register(closeReason: .noReasonCodeSent)

        performServerTest { expectation in
            let testString = "Testing, 1,2,3"
            let dataPayload = testString.data(using: String.Encoding.utf16)!
            let payload = NSMutableData()
            payload.append(dataPayload)

            let expectedPayload = NSMutableData()
            var part = self.payload(closeReasonCode: .invalidDataContents)
            expectedPayload.append(part.bytes, length: part.length)
            part = self.payload(text: "Failed to convert received payload to UTF-8 String")
            expectedPayload.append(part.bytes, length: part.length)

            self.performTest(framesToSend: [(true, self.opcodeText, payload)],
                             expectedFrames: [(true, self.opcodeClose, expectedPayload)],
                             expectation: expectation)
        }
    }

    func testInvalidUTFCloseMessage() {
        register(closeReason: .noReasonCodeSent)

        performServerTest { expectation in
            let testString = "Testing, 1,2,3"
            let dataPayload = testString.data(using: String.Encoding.utf16)!
            let payload = NSMutableData()
            let closeReasonCode = self.payload(closeReasonCode: .normal)
            payload.append(closeReasonCode.bytes, length: closeReasonCode.length)
            payload.append(dataPayload)

            let expectedPayload = NSMutableData()
            var part = self.payload(closeReasonCode: .invalidDataContents)
            expectedPayload.append(part.bytes, length: part.length)
            part = self.payload(text: "Failed to convert received close message to UTF-8 String")
            expectedPayload.append(part.bytes, length: part.length)

            self.performTest(framesToSend: [(true, self.opcodeClose, payload)],
                             expectedFrames: [(true, self.opcodeClose, expectedPayload)],
                             expectation: expectation)
        }
    }

    func testTextAndBinaryFrames() {
        register(closeReason: .protocolError)

        performServerTest { expectation in

            let textPayload = self.payload(text: "testing 1 2 3")
            var bytes = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e]
            let binaryPayload = NSMutableData(bytes: &bytes, length: bytes.count)

            let expectedPayload = NSMutableData()
            var part = self.payload(closeReasonCode: .protocolError)
            expectedPayload.append(part.bytes, length: part.length)
            part = self.payload(text: "A binary frame must be the first in the message")
            expectedPayload.append(part.bytes, length: part.length)

            self.performTest(framesToSend: [(false, self.opcodeText, textPayload),
                                            (true, self.opcodeBinary, binaryPayload)],
                             expectedFrames: [(true, self.opcodeClose, expectedPayload)],
                             expectation: expectation)
        }
    }

    func testUnmaskedFrame() {
        register(closeReason: .protocolError)

        performServerTest { expectation in

            var bytes = [0x00, 0x01]
            let payload = NSMutableData(bytes: &bytes, length: bytes.count)

            let expectedPayload = NSMutableData()
            var part = self.payload(closeReasonCode: .protocolError)
            expectedPayload.append(part.bytes, length: part.length)
            part = self.payload(text: "Received a frame from a client that wasn't masked")
            expectedPayload.append(part.bytes, length: part.length)
            self.performTest(framesToSend: [(true, self.opcodeBinary, payload)], masked: [false],
                             expectedFrames: [(true, self.opcodeClose, expectedPayload)],
                             expectation: expectation)
        }
    }
    
    func testInvalidRSVCode() {
        register(closeReason: .protocolError)
        
        var bytes = [0x00, 0x01]
        let payload = NSMutableData(bytes: &bytes, length: bytes.count)
        
        
        performServerTest (asyncTasks: { expectation in
            let expectedPayload = NSMutableData()
            var part = self.payload(closeReasonCode: .protocolError)
            expectedPayload.append(part.bytes, length: part.length)
            part = self.payload(text: "RSV3 must be 0 unless negotiated to define meaning for non-zero values")
            expectedPayload.append(part.bytes, length: part.length)
            // 25 becomes 0011001 which is a ping (op code 9) and rsv3 = 1
            self.performTest(framesToSend: [(true, 25, payload)],
                             expectedFrames: [(true, self.opcodeClose, expectedPayload)],
                             expectation: expectation)
            
        }, { expectation in
            let expectedPayload = NSMutableData()
            var part = self.payload(closeReasonCode: .protocolError)
            expectedPayload.append(part.bytes, length: part.length)
            part = self.payload(text: "RSV2 must be 0 unless negotiated to define meaning for non-zero values")
            expectedPayload.append(part.bytes, length: part.length)
            // 41 becomes 0101001 which is a ping (op code 9) and rsv2 = 1
            self.performTest(framesToSend: [(true, 41, payload)],
                             expectedFrames: [(true, self.opcodeClose, expectedPayload)],
                             expectation: expectation)
        },{ expectation in
            let expectedPayload = NSMutableData()
            var part = self.payload(closeReasonCode: .protocolError)
            expectedPayload.append(part.bytes, length: part.length)
            part = self.payload(text: "RSV1 must be 0 unless negotiated to define meaning for non-zero values")
            expectedPayload.append(part.bytes, length: part.length)
            // 74 becomes 1001001 which is a ping (op code 9) and rsv1 = 1
            self.performTest(framesToSend: [(true, 73, payload)],
                             expectedFrames: [(true, self.opcodeClose, expectedPayload)],
                             expectation: expectation)
        }, { expectation in
            // 73 becomes 1001001 which is a ping and rsv1 is set to 1, set negotiateCompression
            // ensures compression is negotiated
            self.performTest(framesToSend: [(true, 73, payload)],
                             expectedFrames: [(true, self.opcodePong, payload)],
                             expectation: expectation, negotiateCompression: true, compressed: true)
        })
    }
}
