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
import NIO
import NIOHTTP1
import NIOWebSocket

class WebSocketClient {

    var httpClientHandler = HTTPClientHandler()
    let requestKey: String
    let host: String
    let port: Int
    let uri: String
    private var _channel: Channel? = nil
    var delegate: WebSocketClientDelegate
    let channelAccessQueue: DispatchQueue = DispatchQueue(label: "Channel Access Synchronization")

    public init?(host: String, port: Int, uri: String, requestKey: String) {
        self.requestKey = requestKey
        self.host = host
        self.port = port
        self.uri = uri
        self.delegate = DummyDelegate()
        do {
            try connect()
        } catch {
            return nil
        }
    }

    var channel: Channel? {
        get {
            channelAccessQueue.sync {
                return _channel!
            }
        }
        set {
            channelAccessQueue.sync {
                _channel = newValue
            }
        }
    }

    public var isConnected: Bool {
        return (channel?.isActive)!
    }

    private func connect() throws {
        let bootstrap = ClientBootstrap(group: MultiThreadedEventLoopGroup(numberOfThreads: 1))
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEPORT), value: 1)
            .channelInitializer(self.clientChannelInitializer)
        let channel = try bootstrap.connect(host: self.host, port: self.port).wait()
        var request = HTTPRequestHead(version: HTTPVersion.http11, method: .GET, uri: uri)
        var headers = HTTPHeaders()
        headers.add(name: "Host", value: "\(self.host):\(self.port)")
        request.headers = headers
        channel.write(NIOAny(HTTPClientRequestPart.head(request)), promise: nil)
        _ = channel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)))
        self.channel = channel
    }

    func clientChannelInitializer(channel: Channel)  -> EventLoopFuture<Void> {
        let basicUpgrader = NIOWebClientSocketUpgrader(requestKey: "test") { channel, response in
            self.delegate.connectionEstablished(channel)
            return channel.pipeline.addHandler(WebSocketMessageHandler(client: self))
        }
        let config: NIOHTTPClientUpgradeConfiguration = (upgraders: [basicUpgrader], completionHandler: { context in
            context.channel.pipeline.removeHandler(self.httpClientHandler, promise: nil)
        })
        return channel.pipeline.addHTTPClientHandlers(withClientUpgrade: config).flatMap {
            channel.pipeline.addHandler(self.httpClientHandler)
        }
    }

    public func sendMessage(data: ByteBuffer) {
        //Needs implementation
    }

    public func ping(data: ByteBuffer) {
        //Needs implementation
    }

    public func pong(data: ByteBuffer) {
        let frame = WebSocketFrame(fin: true, opcode: .pong, data: data)
        guard let channel = channel else { return }
        channel.writeAndFlush(frame, promise: nil)
    }

    public func close() {
        //Needs implementation
    }
}

class WebSocketMessageHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = WebSocketFrame

    private let client: WebSocketClient

    private var buffer: ByteBuffer

    public init(client: WebSocketClient) {
        self.client = client
        self.buffer = ByteBufferAllocator().buffer(capacity: 0)
    }

    private func unmaskedData(frame: WebSocketFrame) -> ByteBuffer {
        var frameData = frame.data
        if let maskingKey = frame.maskKey {
            frameData.webSocketUnmask(maskingKey)
        }
        return frameData
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = self.unwrapInboundIn(data)
        switch frame.opcode {
        case .text, .binary, .continuation:
            var data = unmaskedData(frame: frame)
            if frame.opcode == .continuation {
                buffer.writeBuffer(&data)
            } else {
                buffer = data
            }
            if frame.fin {
                client.delegate.messageRecieved(buffer)
            }
        case .ping:
            client.delegate.onPing(unmaskedData(frame: frame))
        case .connectionClose:
            client.delegate.connectionClosed(context.channel)
        case .pong:
            client.delegate.onPong()
        default:
            break
        }
    }
}

class HTTPClientHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart
}

extension HTTPVersion {
    static let http11 = HTTPVersion(major: 1, minor: 1)
}

// Call backs function delegate
protocol WebSocketClientDelegate {

    /// Adds a callback method which is called on successful connection establishment
    func connectionEstablished(_ channel: Channel) -> Void

    /// Adds a callback method which is called on connection closure
    func connectionClosed(_ channel: Channel) -> Void

    /// Adds a callback method which is called when message is recieved
    func messageRecieved(_ data: ByteBuffer) -> Void

    /// Adds a callback method which is called when ping message reception
    func onPing(_ data: ByteBuffer) -> Void

    /// Adds a callback method which is called when client receieves pong
    func onPong() -> Void

    /// Adds a callback method which is called when connection fails to upgrade
    func upgradeFailed(_ channel: Channel) -> Void
}

extension WebSocketClientDelegate {
    func connectionEstablished(_ channel: Channel) -> Void { }

    func connectionClosed(_ channel: Channel) -> Void { }

    func messageRecieved(_ data: ByteBuffer) -> Void { }

    func onPing(_ data: ByteBuffer) -> Void { }

    func onPong() -> Void { }

    func upgradeFailed(_ channel: Channel) -> Void { }
}

// Dummy Websocket client delegate object
class DummyDelegate: WebSocketClientDelegate { }
