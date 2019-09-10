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
import NIOConcurrencyHelpers

class WebSocketClient {

    var httpClientHandler = HTTPClientHandler()
    let requestKey: String
    let host: String
    let port: Int
    let uri: String
    private var _channel: Channel? = nil
    var delegate: WebSocketDelegate? = nil
    let channelAccessQueue: DispatchQueue = DispatchQueue(label: "Channel Access Synchronization")

    public init?(host: String, port: Int, uri: String, requestKey: String) {
        self.requestKey = requestKey
        self.host = host
        self.port = port
        self.uri = uri
        do {
            try connect()
        } catch {
            return nil
        }
    }

    var channel: Channel {
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
        return channel.isActive
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
            self.delegate?.open(channel)
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
                client.delegate?.message(buffer)
            }
        case .ping:
            client.delegate?.ping(unmaskedData(frame: frame))
        case .connectionClose:
            client.delegate?.close(context.channel)
        case .pong:
            client.delegate?.pong()
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

protocol WebSocketDelegate {

    func open(_ channel: Channel) -> Void

    func close(_ channel: Channel) -> Void

    func message(_ data: ByteBuffer) -> Void

    func ping(_ data: ByteBuffer) -> Void

    func pong() -> Void

    func upgradeFailure(_ channel: Channel) -> Void
}

extension WebSocketDelegate {
    func open(_ channel: Channel) -> Void { }

    func close(_ channel: Channel) -> Void { }

    func message(_ channel: ByteBuffer) -> Void { }

    func ping(_ channel: ByteBuffer) -> Void { }

    func pong() -> Void { }

    func upgradeFailure(_ channel: Channel) -> Void { }
}

