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

import Foundation
import KituraNet
import Dispatch
import KituraWebSocket

// A test WebSocket service used for running Autobahn tests in the CI
class EchoService: WebSocketService {

    public func connected(connection: WebSocketConnection) {}

    public func disconnected(connection: WebSocketConnection, reason: WebSocketCloseReasonCode) {}

    public func received(message: Data, from: WebSocketConnection) {
        from.send(message: message)
    }

    public func received(message: String, from: WebSocketConnection) {
        from.send(message: message)
    }

    public let connectionTimeout: Int? = 20
}

WebSocket.register(service: EchoService(), onPath: "/")
let port = 9001

do {
    _ = try HTTPServer.listen(on: port, delegate: nil)
} catch {
    print("Unable to start server")
}

dispatchMain()
