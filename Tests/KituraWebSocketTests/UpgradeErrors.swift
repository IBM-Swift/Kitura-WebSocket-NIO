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
import NIOHTTP1

@testable import KituraWebSocket
@testable import KituraNet

class UpgradeErrors: KituraTest {

    static var allTests: [(String, (UpgradeErrors) -> () throws -> Void)] {
        return [
            ("testNoService", testNoService)
        ]
    }

    func testNoService() {
        WebSocket.factory.clear()
        performServerTest { expectation in
            guard let client = WebSocketClient(host: "localhost", port: 8080, uri: self.servicePath, requestKey: self.secWebKey) else { return }
            client.onError { error, status in
                XCTAssertEqual(status?.code, WebSocketClientError.badRequest.code(),
                               "Server response status code \(String(describing: status?.code)) is not equal to recieved error \(String(describing: WebSocketClientError.webSocketUrlNotRegistered.code()))")
                expectation.fulfill()
            }
            client.connect()
        }
    }
}
