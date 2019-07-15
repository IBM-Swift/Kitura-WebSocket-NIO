## WebSocket Compression
WebSocket Compression, defined by [RFC7692](https://tools.ietf.org/html/rfc7692) allows WebSocket clients to send and receive compressed data on a WebSocket connection. Compression reduces the total wire-level payload of a WebSocket connection, possibly resulting in an improved throughput.

This document discusses the implementation of WebSocket Compression in [Kitura-WebSocket-NIO](https://github.com/IBM-Swift/Kitura-WebSocket-NIO), which is an implementation of the [Kitura-WebSocket](https://github.com/IBM-Swift/Kitura-WebSocket) API using [SwiftNIO](https://github.com/apple/swift-nio).

This document assumes the reader is aware of the fundamentals of the [WebSocket protocol](https://tools.ietf.org/html/rfc6455).

### Table of contents
1. [WebSocket extensions](https://gist.github.com/pushkarnk/aea1be88c7c7283fcfe4615df35ed857#1-websocket-extensions)
2. [WebSocket compression - the `permessage-deflate` algorithm](https://gist.github.com/pushkarnk/aea1be88c7c7283fcfe4615df35ed857#2-the-permessage-deflate-algorithm)
3. [An implementation of permessage-deflate based on SwiftNIO](https://gist.github.com/pushkarnk/aea1be88c7c7283fcfe4615df35ed857#3-an-implementation-of-permessage-deflate-based-on-swift-nio)
4. [Developer notes](https://gist.github.com/pushkarnk/aea1be88c7c7283fcfe4615df35ed857#4-developer-notes)

### 1. WebSocket extensions
The WebSocket protocol has a provision for servers to configure protocol extensions, and for clients to request these extensions from the servers. A client notifies about extensions it is interested in through a `negotiation offer` using the `Sec-WebSocket-Extension` header. A server may or may not support the extensions requested by the client. Through a `negotiation response`, the server notifies the client of the extensions that the server agrees upon. Negotiation offers and responses may also include extension-specific parameters. Once an extension is agreed upon, the client and server must invoke the extension from their respective WebSocket implementations.

WebSocket compression is a WebSocket extension.

### 2. WebSocket Compression: the permessage-deflate algorithm
Permessage-deflate is a WebSocket extension defined by [RFC7692](https://tools.ietf.org/html/rfc7692) which provides a specification for the compression functionality. It defines the negotiation process and a compression algorithm called `DEFLATE`. Like any WebSocket extension, the permessage-deflate negotiation comprises of an offer and a response. 

###### The permessage-deflate negotiation offer
A `permessage-deflate` negotiation happens during the upgrade request from HTTP to WebSocket. A `permessage-deflate` negotiation offer has a mandatory `permessage-deflate` string followed by a semi-colon separated list of extension parameters. There are four extension parameters defined for WebSocket compression:
 - `client_no_context_takeover`, `server_no_context_takeover`
 - `client_max_window_bits`, `server_max_window_bits`

We will revisit these parameters in a later section, where we will discuss their use and effects.

###### The permessage-deflate negotiation response
A permessage-deflate negotiation response has a mandatory `permessage-deflate` string followed by a semi-colon separated list of extension parameters, agreed upon by the server. The headers in the negotiation response are the final word on how the data compression/decompression will be done between the client and server. Data compressed by the client must be decompressed by the server and vice versa. The client and server must adopt the same compression/decompression configuration parameters. We will take a detailed look at this in the later sections.

The specification also discusses the DEFLATE algorithm. We utilize the [zlib compression library](https://www.zlib.net) for doing raw compression and decompression. A pair, comprising of a compressor and a decompressor, must be set up at both the ends of the connection. The server's decompressor decompresses messages compressed by the client's compressor and vice versa.

### 3. An implementation of permessage-deflate based on SwiftNIO 
The [SwiftNIO](https://github.com/apple/swift-nio) framework provides an API which enables HTTP/WebSocket server implementations to view the processing of data, that has been read from or written to sockets, as a sequence of transformations that happen through a pipeline of handlers. An active connection is represented by a `Channel`. Data which is read from, or written to, a channel moves through a `ChannelPipeline` of inbound and outbound `ChannelHandlers`. An `EventLoop` is associated with every `Channel`. An `EventLoop` is a thread-safe abstraction of a thread and provides features for asynchronous code execution using `EventLoopFutures` and `EventLoopPromises`.

In [Kitura-NIO](https://github.com/IBM-Swift/Kitura-NIO), we start the HTTP server with the pipeline configured by SwiftNIO, adding Kitura-NIO's `HTTPRequestHandler` at the end. A view of the inbound and outbound pipelines (with some handlers omitted for simplicity) is this:

 - Inbound channel handler pipeline: 

    *(Operating System)*   
         \|      
    `NIOSSLServerHandler`    
         \|  
    `HTTPDecoder`     
         \|  
    `HTTPRequestHandler`    
         \|   
    *(Kitura/WebSocket app)*  
    
 - Outbound channel handler pipeline: 

    *(Kitura/WebSocket app)*  
    \|  
    `HTTPEncoder`  
    \|  
    `NIOSSLServerHandler`  
    \|  
    *(Operating System)*   

[HTTPDecoder](https://apple.github.io/swift-nio/docs/current/NIOHTTP1/Classes/HTTPDecoder.html) and [HTTPResponseEncoder](https://apple.github.io/swift-nio/docs/current/NIOHTTP1/Classes/HTTPResponseEncoder.html) convert bytes to HTTP requests, and responses to bytes, respectively. [NIOSSLServerHandler](https://apple.github.io/swift-nio-ssl/docs/current/NIOSSL/Classes/NIOSSLServerHandler.html) is a duplex handler (both inbound and outbound) used to decrypt and encrypt data on a secure connection. The [HTTPRequestHandler](https://github.com/IBM-Swift/Kitura-NIO/blob/master/Sources/KituraNet/HTTP/HTTPRequestHandler.swift) is used to invoke Kitura's router.

An upgrade to WebSocket causes SwiftNIO to alter the above pipeline in these ways:
 - the `HTTPDecoder` and `HTTPResponseEncoder` (and other HTTP related handlers) are removed from the pipeline
 - an inbound handler [WebSocketFrameDecoder](https://apple.github.io/swift-nio/docs/current/NIOWebSocket/Classes/WebSocketFrameDecoder.html) is added. It convert raw bytes, received on the wire, to WebSocket frames. 
 - an outbound handler [WebSocketFrameEncoder](https://apple.github.io/swift-nio/docs/current/NIOWebSocket/Classes/WebSocketFrameEncoder.html) is added to convert WebSocket frames to raw bytes to be sent on the wire. 

Additionally, `Kitura-WebSocket-NIO` makes the following changes to the pipeline:
 - adds `WebSocketConnection`, an inbound handler to process received WebSocket messages
 - if the `permessage-deflate` negotiation goes through, a `PermessageDeflateCompressor` and `PermessageDeflateDecompressor` are added
 
 The pipelines now look like:
 - Inbound pipeline: 
 
   *(Operating System)*  
    \|  
   `NIOSSLServerHandler`  
    \|   
   `WebSocketFrameDecoder`  
    \|  
   `PermessageDeflateDecompressor`  
    \|  
   `WebSocketConnection`  
    \|  
   *(Kitura/WebSocket application)*

 - Outbound pipeline:  
 
   *(Kitura/WebSocket application)*  
    \|  
   `PermessageDeflaterCompressor`    
    \|  
   `WebSocketFrameEncoder`      
    \|  
   `NIOSSLServerHandler`  
    \|  
   *(Operating System)*    
 
 [PermessageDeflateCompressor](https://github.com/IBM-Swift/Kitura-WebSocket-NIO/blob/master/Sources/KituraWebSocket/PermessageDeflateCompressor.swift) is an outbound handler used to compress outbound WebSocket messages. [PermessageDeflateDecompressor](https://github.com/IBM-Swift/Kitura-WebSocket-NIO/blob/master/Sources/KituraWebSocket/PermessageDeflateDecompressor.swift) is an inbound handler used to decompress inbound WebSocket messages. Every WebSocket connection where a valid `permessage-deflate` compression was negotiated, gets its own (`PermessageDeflateCompressor`, `PermessageDeflateDecompressor`) pair. 
 
 With this setup, all the inbound data first passes through SwiftNIO's [WebSocketDecoder](https://apple.github.io/swift-nio/docs/current/NIOWebSocket/Classes/WebSocketFrameDecoder.html) where the WebSocket frames are built. It then moves into the `PermessageDeflateDecompressor` where multiple frames comprising a message are accumulated and decompressed using `zlib`'s inflater. Subsequently, the decompressed messages are moved to the `WebSocketConnection` handler.

Outbound WebSocket frames first reach the `PermessageDeflateCompressor` which compresses the data held within them and relays them to the [WebSocketEncoder](https://apple.github.io/swift-nio/docs/current/NIOWebSocket/Classes/WebSocketFrameEncoder.html). Here the frames are marshalled into raw bytes to be written to the wire after encryption.

#### 3.1 Compressor implementation
The compressor is called `PermessageDeflateCompressor`. It is a [ChannelOutboundHandler](https://apple.github.io/swift-nio/docs/current/NIO/Protocols/ChannelOutboundHandler.html).

`ChannelOutboundHandler`'s `write(context:data:promise)` method implemented here gets invoked when the previous outbound handler (`WebSocketConnection`) writes data to the channel. Here, only data frames and continuation frames are processed. A WebSocket message is either available in a single data frame or a data frame followed by sequence of continuation frames. 

The compressor makes sure that we have all the data pertaining to a message accumulated. Subsequently, `zlib`'s deflater is invoked and deflated data is packed into a new WebSocketFrame, which is passed to the `WebSocketFrameEncoder`.

#### 3.2 Decompressor implementation
The decompressor is, functionally, a mirror image of the compressor. It is called `PermessageDeflateDecompressor` and is a [ChannelInboundHandler](https://apple.github.io/swift-nio/docs/current/NIO/Protocols/ChannelInboundHandler.html).

`ChannelInboundHandler`'s `channelRead(context:data)` method implemented here is invoked whenever a new `WebSocketFrame` is produced by the `WebSocketDecoder`. Similar to the compressor, the decompressor processes data and continuation frames only. All the data pertaining to a message, possibly spread across continuation frames, is accumulated and `zlib`'s inflater is invoked. The inflated data is then packed into a new `WebSocketFrame` and moved into the next handler in the pipeline.

#### 3.3 Configuring the Compressor and Decompressor
[RFC7692](https://tools.ietf.org/html/rfc7692) defines four configuration options. They are actually two pairs of option, one each for the client and the server:

###### 3.3.1 `client_no_context_takeover` and `server_no_context_takeover` 
These allow the client and server to use a new zlib inflater or deflater on every message. By default we reuse the inflater and deflater instances across messages. This means the inflater and deflater are initialized only once. The memory allocation/deallocation happens only once and the history of the deflate/inflate stream can be reused. [Here](https://tools.ietf.org/html/rfc7692#section-7.2.3.2) is an example.

In the `Kitura-WebSocket-NIO` implementation:
 - a client can inform the server that it isn't using context takeover by sending the `client_no_context_takeover` extension parameter. The server will respond with the same `client_no_context_takeover` parameter and configure its decompressor to not use context takeover.
 - a client can request the server to not use context takeover by sending the `server_no_context_takeover` extension parameter. The server will regard this request and configure its compressor to not use context takeover. It will add the `server_no_context_takeover` parameter in the response.
 - by default the server will configure its compressor and decompressor to use context takeover i.e. to reuse compression context

###### 3.3.2 `client_max_window_bits` and `server_max_window_bits` 
These allow the client and server to share the LZ77 sliding window size. The default value is 15 bits which represents a window size of 32768 (2^15). The client's compressor and the server's decompressor must have the same LZ77 window size. The same restriction applies to the server's compressor and the client's decompressor.

In the `Kitura-WebSocket-NIO` implementation:
- a client can inform the server of its compressor's LZ77 window size using the `client_max_window_bits` extension parameter. If the parameter has a valid value, the server will configure its decompressor accordingly and send the same extension parameter in the response, indicating an agreement.
- a client can also request the server to use a particular  LZ77 window size using the `server_max_window_bits` extension parameter. If the value is valid, the server will configure its compressor accordingly and send the same extension parameter in the response, indicating an agreement.

### 4. Developer notes
1. The `PermessageDeflateCompressor` and `PermessageDeflaterDecompressor` both consolidate multi-frame messages into a single frame. This loss of framing information may not be serious in typical use-cases. But there may be applications where framing information has to be maintained.

2. As mentioned in one of the examples [here](https://tools.ietf.org/html/rfc7692#section-7.1.3), a client may supply fallback negotiation offers, in case negotiation fails. `Kitura-WebSocket-NIO` hasn't implemented this. We make sure every offer goes through.

3. The LZ77 sliding window value must be passed as a negative parameter to deflateInit2()/inflateInit2(). This informs `zlib` that we use raw deflate streams (as against zlib streams that result with sliding window positive values). See [this](https://github.com/IBM-Swift/Kitura-WebSocket-NIO/pull/26/commits/52614a23dbff37db18e2c0fb70e282921c0bb666).

4. There's an open zlib bug with a sliding window size of 8 bits. See [this](https://github.com/madler/zlib/issues/171). There is a workaround for zlib streams. We implement a similar workaround for raw deflate streams [here](https://github.com/IBM-Swift/Kitura-WebSocket-NIO/pull/26/commits/c9d9b44d56de7c398a526b34dacf7b4302045f73).

5. Clients may negotiate for compression but send uncompressed frames. To handle this, just before decompressing, we check the RSV1 bit of the first frame to make sure it belongs to a compressed message.

6. SwiftNIO offers a [ChannelDuplexHandler](https://apple.github.io/swift-nio/docs/current/NIO/Typealiases.html#/s:3NIO20ChannelDuplexHandlera) type for channel handlers that are a part of both, the inbound and outbound pipelines. The `PermessageDeflateCompressor` and `PermessageDeflateDecompressor` could be merged into a single `ChannelDuplexHandler`.


