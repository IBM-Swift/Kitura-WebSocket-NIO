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
import NIOSSL
import NIOWebSocket
import Dispatch
import XCTest
import WebSocketCompression

#if os(Linux)
    import Glibc
#endif

// A global EventLoopGroup for the WebSocketClient to use.
fileprivate let wsClientGlobalELG = MultiThreadedEventLoopGroup(numberOfThreads: 1)

class WebSocketClient {

    let requestKey: String
    let host: String
    let port: Int
    let uri: String
    var channel: Channel? = nil
    public var negotiateCompression: Bool
    public var maxWindowBits: Int32
    public var contextTakeover: ContextTakeover
    public var maxFrameSize: Int

    //  This semaphore signals when the client successfully recieves the Connection upgrade response from remote server
    //  Ensures that webSocket frames are sent on channel only after the connection is successfully upgraded to WebSocket Connection

    let upgraded = DispatchSemaphore(value: 0)

    let callBackSync = DispatchQueue(label: "callback.sync.queue")

    // Create a new `WebSocketClient`.
    //
    //
    //         Example usage:
    //             let client = WebSocketClient(host: "localhost", port: 8080, uri: "/", requestKey: "test")
    //
    //         // See RFC 7692 for to know more about compression negotiation
    //         Example usage with compression enabled:
    //             let client = WebSocketClient(host: "localhost", port: 8080, uri: "/", requestKey: "test", negotiateCompression: true)
    //
    // - parameters:
    //     - host: Host name of the remote server
    //     - port: Port number on which the remote server is listening
    //     - uri : The "Request-URI" of the GET method, it is used to identify the endpoint of the WebSocket connection
    //     - requestKey: The requestKey sent by client which server has to include while building it's response. This helps ensure that the server
    //                   does not accept connections from non-WebSocket clients
    //     - negotiateCompression: Parameter to negotiate compression. Setting this parameter to `true` adds the Headers neccesary for negotiating compression
    //                              with server while building the upgrade request. This parameter is set to `false` by default.
    //     - maxWindowbits: Size of the LZ77 sliding window used in compression, valid values are between 8..15 bits.
    //                      An endpoint is by default configured with value of 15.
    //     - contextTakeover: Parameter to configure the Context Takeover of the WebSocket Connection.
    //     - maxFrameSize : Maximum allowable frame size of WebSocket client is configured using this parameter.
    //                      Default value is `14`.

    public init?(host: String, port: Int, uri: String, requestKey: String,
                 negotiateCompression: Bool = false, maxWindowBits: Int32 = 15,
                 contextTakeover: ContextTakeover = .both, maxFrameSize: Int = 24, onOpen: @escaping (Channel?) -> Void = { _ in }) {
        self.requestKey = requestKey
        self.host = host
        self.port = port
        self.uri = uri
        self.onOpenCallback = onOpen
        self.negotiateCompression = negotiateCompression
        self.maxWindowBits = maxWindowBits
        self.contextTakeover = contextTakeover
        self.maxFrameSize = maxFrameSize
    }

    public init?(_ urlString: String = "ws://localhost:8080/") {
        self.requestKey = "test"
        let url = URL(string: urlString)
        self.host = (url!.host!)
        self.port = (url!.port!)
        self.uri = url!.path
        self.maxFrameSize = 24
        self.negotiateCompression = false
        self.maxWindowBits = 15
        self.contextTakeover = .both
     }

    let group = wsClientGlobalELG

    public var delegate: WebSocketClientDelegate? = nil

    // Whether close frame is sent to server
    var closeSent: Bool = false

    // Whether the client is still alive
    public var isConnected: Bool {
        return channel?.isActive ?? false
    }

    public func connect() {
        do {
            try makeConnection()
        } catch {
            return
        }
    }

    //  Used only for testing
    //  Decides whether the websocket frame sent has to be masked or not
    public var maskFrame: Bool = true

    // This function pings to the connected server
    //
    //             client.ping()
    //
    // - parameters:
    //     - data: ping frame payload, must be less than 125 bytes

    public func ping(data: ByteBuffer = ByteBufferAllocator().buffer(capacity: 0)) {
        sendMessage(data: data, opcode: .ping)
    }

    // Sends a pong frame to the connected server
    //
    //             client.pong()
    //
    // - parameters:
    //     - data: frame payload, must be less than 125 bytes

    public func pong(data: ByteBuffer = ByteBufferAllocator().buffer(capacity: 0)) {
        sendMessage(data: data, opcode: .pong)
    }

    // This function closes the connection
    //
    //             client.close()
    //
    // - parameters:
    //     - data: close frame payload, must be less than 125 bytes

    public func close(data: ByteBuffer = ByteBufferAllocator().buffer(capacity: 0)) {
        closeSent = true
        sendMessage(data: data, opcode: .connectionClose)
    }

    // This function sends text-formatted data to the connected server
    //
    //             client.sendMessage("Hello World")
    //
    // - parameter:
    //     - `text`: Text-formatted data to be sent to the connected server

    public func sendMessage(_ string: String) {
        var buffer = ByteBufferAllocator().buffer(capacity: string.count)
        buffer.writeString(string)
        sendMessage(data: buffer, opcode: .text)
    }

    // This function sends binary-formatted data to the connected server
    //
    //             client.sendMessage([0x11,0x12])
    //
    // - parameter:
    //     - `binary`: binary-formatted data to be sent to the connected server

    public func sendMessage(_ binary: [UInt8]) {
        sendMessage(raw: binary, opcode: .binary)
    }

    // This function sends binary-formatted data to the connected server in multiple frames
    //
    //             // server recieves [0x11 ,0x12, 0x13] when following is sent
    //             client.sendMessage(raw: [0x11,0x12], opcode: .binary, finalFrame: false)
    //             client.sendMessage(raw: [0x13], opcode: .continuation, finalFrame: true)
    //
    // - parameters:
    //     - raw: raw binary data to be sent in the frame
    //     - opcode: Websocket opcode indicating type of the frame
    //     - finalFrame: Whether the frame to be sent is the last one, by default this is set to `true`
    //     - compressed: Whether to compress the current frame to be sent, by default compression is disabled

    public func sendMessage<T>(raw binary: T, opcode: WebSocketOpcode = .binary, finalFrame: Bool = true, compressed: Bool = false)
        where T: Collection, T.Element == UInt8 {
        var buffer = ByteBufferAllocator().buffer(capacity: binary.count)
        buffer.writeBytes(binary)
        sendMessage(data: buffer, opcode: opcode, finalFrame: finalFrame, compressed: compressed)
    }

    // This function sends text-formatted data to the connected server in multiple frames
    //
    //             // server recieves "Kitura-WebSocket-NIO" when following is sent
    //             client.sendMessage(raw: "Kitura-WebSocket", opcode: .text, finalFrame: false)
    //             client.sendMessage(raw: "-NIO", opcode: .continuation, finalFrame: true)
    //
    // - parameters:
    //     - raw: raw text to be sent in the frame
    //     - opcode: Websocket opcode indicating type of the frame
    //     - finalFrame: Whether the frame to be sent is the last one, by default this is set to `true`
    //     - compressed: Whether to compress the current frame to be sent, by default this set to `false`

    public func sendMessage<T>(raw data: T, opcode: WebSocketOpcode = .text, finalFrame: Bool = true, compressed: Bool = false)
        where T: Collection, T.Element == Character {
        let string = String(data)
        var buffer = ByteBufferAllocator().buffer(capacity: string.count)
        buffer.writeString(string)
        sendMessage(data: buffer, opcode: opcode, finalFrame: finalFrame, compressed: compressed)
    }

    public func sendMessage<T>(model: T, opcode: WebSocketOpcode = .text, finalFrame: Bool = true, compressed: Bool = false) where T: Codable {
        let jsonEncoder = JSONEncoder()
        do {
            let jsonData = try jsonEncoder.encode(model)
            let string = String(data: jsonData, encoding: .utf8)!
            var buffer = ByteBufferAllocator().buffer(capacity: string.count)
            buffer.writeString(string)
            sendMessage(data: buffer, opcode: opcode, finalFrame: finalFrame, compressed: compressed)
        } catch let error{
            print(error)
        }
    }

    // This function sends IOData(ByteBuffer) to the connected server
    //
    //             client.sendMessage(data: byteBuffer, opcode: opcode)
    //
    // - parameters:
    //     - data: ByteBuffer-formatted to be sent in the frame
    //     - opcode: Websocket opcode indicating type of the frame
    //     - finalFrame: Whether the frame to be sent is the last one, by default this is set to `true`
    //     - compressed: Whether to compress the current frame to be sent, by default this set to `false`

    public func sendMessage(data: ByteBuffer, opcode: WebSocketOpcode, finalFrame: Bool = true, compressed: Bool = false) {
        send(data: data, opcode: opcode, finalFrame: finalFrame, compressed: compressed)
    }

    //  This function generates masking key to mask the payload to be sent on the WebSocketframe
    //  Data is automatically masked unless specified otherwise by property 'maskFrame'
    func generateMaskingKey() -> WebSocketMaskingKey {
        let mask: [UInt8] = [.random(in: 0..<255), .random(in: 0..<255), .random(in: 0..<255), .random(in: 0..<255)]
        return WebSocketMaskingKey(mask)!
    }

    private func makeConnection() throws {
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEPORT), value: 1)
            .channelInitializer(self.clientChannelInitializer)
        _ = try bootstrap.connect(host: self.host, port: self.port).wait()
        self.upgraded.wait()
    }

    private func clientChannelInitializer(channel: Channel) -> EventLoopFuture<Void> {
        let httpHandler = HTTPClientHandler(client: self)
        let basicUpgrader = NIOWebClientSocketUpgrader(requestKey: self.requestKey, maxFrameSize: 1 << self.maxFrameSize,
                                                       automaticErrorHandling: false, upgradePipelineHandler: self.upgradePipelineHandler)
        let config: NIOHTTPClientUpgradeConfiguration = (upgraders: [basicUpgrader], completionHandler: { context in
            context.channel.pipeline.removeHandler(httpHandler, promise: nil)})
        return channel.pipeline.addHTTPClientHandlers(withClientUpgrade: config).flatMap { _ in
            return channel.pipeline.addHandler(httpHandler)
        }
    }

    private func upgradePipelineHandler(channel: Channel, response: HTTPResponseHead) -> EventLoopFuture<Void> {
        self.onOpenCallback(channel)
        if response.status == .switchingProtocols {
            self.channel = channel
            self.upgraded.signal()
        }
        let slidingWindowBits = windowSize(header: response.headers)
        let deflater = PermessageDeflateCompressor(noContextTakeOver: self.contextTakeover.clientNoContextTakeover,
                                                   maxWindowBits: slidingWindowBits)
        let inflater = PermessageDeflateDecompressor(noContextTakeOver: self.contextTakeover.serverNoContextTakeover,
                                                     maxWindowBits: slidingWindowBits)
        
        if self.negotiateCompression {
            return channel.pipeline.addHandlers([WebSocketCompressor(deflater: deflater), WebSocketDecompressor(inflater: inflater), WebSocketMessageHandler(client: self)])
        } else {
            return channel.pipeline.addHandler(WebSocketMessageHandler(client: self))
        }
    }

    private func send(data: ByteBuffer, opcode: WebSocketOpcode, finalFrame: Bool, compressed: Bool) {
        let mask = self.maskFrame ? self.generateMaskingKey(): nil
        let frame = WebSocketFrame(fin: finalFrame, rsv1: compressed, opcode: opcode, maskKey: mask, data: data)
        guard let channel = channel else { return }
        if finalFrame {
            channel.writeAndFlush(frame, promise: nil)
        } else {
            channel.write(frame, promise: nil)
        }
    }

    // Calculates th LZ77 sliding window size from server response
    private func windowSize(header: HTTPHeaders) -> Int32 {
        return header["Sec-WebSocket-Extensions"].first?.split(separator: ";")
            .dropFirst().first?.split(separator: "=").last.flatMap({ Int32($0)}) ?? self.maxWindowBits
    }

    // Stored callbacks
    var onOpenCallback: (Channel) -> Void  = { _ in }

    var onCloseCallback: (Channel, ByteBuffer) -> Void = { _,_ in }

    var onMessageCallback: (ByteBuffer) -> Void = { _ in }

    var onPingCallback: (ByteBuffer) -> Void = { _ in }

    var onPongCallback: (WebSocketOpcode, ByteBuffer) -> Void = { _,_ in }

    var _errorCallBack: (Error?, HTTPResponseStatus?) -> Void = { _,_ in }

    var onErrorCallBack: (Error?, HTTPResponseStatus?) -> Void {

        get {
            return callBackSync.sync {
                return _errorCallBack
            }
        }
        set {
            _ = callBackSync.sync {
                _errorCallBack = newValue
            }
        }
    }


    // callback functions
    // These functions are called when client gets reply from another endpoint
    //
    //     Example usage:
    //         Consider an endpoint sending data, callback function onMessage is triggered
    //         and receieved data is available as bytebuffer
    //
    //         client.onMessage { receivedData in  // receieved byteBuffer
    //                    // do something with recieved ByteBuffer
    //                 }
    //
    // Other callback functions are used similarly.
    //

    public func onMessage(_ callback: @escaping (ByteBuffer) -> Void) {
        self.executeOnEventLoop { self.onMessageCallback = callback }
    }

    public func onOpen(_ callback: @escaping (Channel) -> Void) {
        self.executeOnEventLoop { self.onOpenCallback = callback }
    }

    public func onClose(_ callback: @escaping (Channel, ByteBuffer) -> Void) {
        self.executeOnEventLoop { self.onCloseCallback = callback }
    }

    public func onPing(_ callback: @escaping (ByteBuffer) -> Void) {
        self.executeOnEventLoop { self.onPingCallback = callback }
    }

    public func onPong(_ callback: @escaping (WebSocketOpcode, ByteBuffer) -> Void) {
        self.executeOnEventLoop { self.onPongCallback = callback }
    }

    public func onError(_ callback: @escaping (Error?, HTTPResponseStatus?) -> Void) {
        self.onErrorCallBack = callback
    }

    private func executeOnEventLoop(_ code: @escaping () -> Void) {
        self.channel?.eventLoop.execute(code)
    }
}

// WebSocket Handler which recieves data over WebSocket Connection
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

    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        if client.delegate != nil {
            client.delegate?.onError(error: error, status: nil)
        } else {
            client.onErrorCallBack(error, nil)
        }
        client.close()
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
                if let delegate = client.delegate {
                    delegate.messageRecieved(data: buffer)
                } else {
                    client.onMessageCallback(buffer)
                }
            }
        case .ping:
            if let delegate = client.delegate {
                delegate.pingRecieved(data: unmaskedData(frame: frame))
            } else {
                client.onPingCallback(unmaskedData(frame: frame))
            }
        case .connectionClose:
            if !client.closeSent {
                client.close(data: frame.data)
            }
            if let delegate = client.delegate {
                delegate.closeMessageRecieved(channel: context.channel, data: frame.data)
            } else {
                client.onCloseCallback(context.channel, frame.data)
            }
        case .pong:
            if let delegate = client.delegate {
                delegate.pongRecieved(data: frame.data)
            } else {
                client.onPongCallback(frame.opcode, frame.data)
            }
        default:
            break
        }
    }
}

// This handler is used to send WebSocketUpgrade ugrade request to server
class HTTPClientHandler: ChannelInboundHandler, RemovableChannelHandler {

    typealias InboundIn = HTTPClientResponsePart
    unowned var client: WebSocketClient

    init(client: WebSocketClient) {
        self.client = client
    }

    func channelActive(context: ChannelHandlerContext) {
        var request = HTTPRequestHead(version: HTTPVersion.http11, method: .GET, uri: client.uri)
        var headers = HTTPHeaders()
        headers.add(name: "Host", value: "\(client.host):\(client.port)")
        if client.negotiateCompression {
            let value = buildExtensionHeader()
            headers.add(name: "Sec-WebSocket-Extensions", value: value)
        }
        request.headers = headers
        context.channel.write(NIOAny(HTTPClientRequestPart.head(request)), promise: nil)
        context.channel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let response = unwrapInboundIn(data)
        switch response {
        case .head(let header) :
            if let delegate = client.delegate {
                switch header.status {
                case .badRequest:
                    delegate.onError(error: WebSocketClientError.badRequest, status: header.status)
                case .notFound:
                    delegate.onError(error: WebSocketClientError.webSocketUrlNotRegistered, status: header.status)
                default :
                    break
                }
            } else {
                switch header.status {
                case .badRequest:
                    client.onErrorCallBack(WebSocketClientError.badRequest, header.status)
                case .notFound:
                    client.onErrorCallBack(WebSocketClientError.webSocketUrlNotRegistered, header.status)
                default :
                    break
                }
            }
        case .body(_):
            break
        case .end(_):
            break
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if client.delegate != nil {
            client.delegate?.onError(error: error, status: nil)
        } else {
        client.onErrorCallBack(error, nil)
        }
    }

    //  Builds extension headers based on the configuration of maxwindowbits ,context takeover
    func buildExtensionHeader() -> String {
        var value = "permessage-deflate"
        if client.maxWindowBits >= 8 && client.maxWindowBits < 15 {
            value.append("; " + "client_max_window_bits; server_max_window_bits=" + String(client.maxWindowBits))
        }
        value.append(client.contextTakeover.header())
        return value
    }

}

extension HTTPVersion {
    static let http11 = HTTPVersion(major: 1, minor: 1)
}

//  This enum is used to populate 'Sec-WebSocket-Extension' field of upgrade header with user required ContextTakeover configuration
//  User specifies the the context Takeover configuration when creating the WebSocketClient
//  when not specified both the client and server connections are context takeover enabled

enum ContextTakeover {
    case none
    case client
    case server
    case both

    func header() -> String {
        switch self {
        case .none: return "; client_no_context_takeover; server_no_context_takeover"
        case .client: return "; server_no_context_takeover"
        case .server: return "; client_no_context_takeover"
        case .both: return ""
        }
    }

    var clientNoContextTakeover: Bool {
        return self != .client && self != .both
    }

    var serverNoContextTakeover: Bool {
        return self != .server && self != .both
    }
}

// WebSocket Client errors
enum WebSocketClientError: UInt, Error {
    case webSocketUrlNotRegistered = 404
    case badRequest = 400

    func code() -> UInt? {
        switch self {
        case .webSocketUrlNotRegistered :
            return 404
        case .badRequest :
            return 400
        }
    }
}

// Protocol to delegate callbacks. These functions are called when client gets reply from another endpoint
public protocol WebSocketClientDelegate {

    // Called when message is recieved from server
    func messageRecieved(data: ByteBuffer)

    // Called when ping is recieved from server
    func pingRecieved(data: ByteBuffer)

    // Called when pong is recieved from server
    func pongRecieved(data: ByteBuffer)

    // Called when close message is recieved from server
    func closeMessageRecieved(channel: Channel, data: ByteBuffer)

    // Called when errored is recieved from server
    func onError(error: Error?, status: HTTPResponseStatus?)
}

extension WebSocketClientDelegate {

    func messageRecieved(data: ByteBuffer) {}

    func pingRecieved(data: ByteBuffer) {}

    func pongRecieved(data: ByteBuffer) {}

    func closeMessageRecieved(channel: Channel, data: ByteBuffer) {}

    func onError(error: Error?, status: HTTPResponseStatus?) {}
}
