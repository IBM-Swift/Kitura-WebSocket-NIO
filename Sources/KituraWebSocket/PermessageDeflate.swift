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

import NIO
import WebSocketCompression

// An extension that implements WebSocket compression through the permessage-deflate algorithm
// RFC 7692: https://tools.ietf.org/html/rfc7692

class PermessageDeflate: WebSocketProtocolExtension {

    // Returns the deflater and inflater, to be subsequently added to the channel pipeline
    func handlers(header: String) -> [ChannelHandler] {
        guard header.hasPrefix("permessage-deflate") else { return [] }
        var deflaterMaxWindowBits: Int32 = 15
        var inflaterMaxWindowBits: Int32 = 15
        var clientNoContextTakeover = false
        var serverNoContextTakeover = false

        // Four parameters to handle:
        // * server_max_window_bits: the LZ77 sliding window size used by the server for compression
        // * client_max_window_bits: the LZ77 sliding window size used by the server for decompression
        // * server_no_context_takeover: prevent the server from using context-takeover
        // * client_no_context_takeover: prevent the client from using context-takeover
        for parameter in header.components(separatedBy: "; ") {
            // If we receieved a valid value for server_max_window_bits, use it to configure the deflater
            if parameter.hasPrefix("server_max_window_bits") {
                let maxWindowBits = parameter.components(separatedBy: "=")
                guard maxWindowBits.count == 2 else { continue }
                guard let mwBits = Int32(maxWindowBits[1]) else { continue }
                if mwBits >= 8 && mwBits <= 15 {
                    // We received a valid value. However there's a special case here:
                    //
                    // There's an open zlib issue which does not set the window size
                    // to 256 (windowBits=8). For windowBits=8, zlib silently changes the
                    // value to 9. However, this apparent hack works only with zlib streams.
                    // WebSockets use raw deflate streams. For raw deflate streams, zlib has been
                    // patched to ignore the windowBits value 8.
                    // More details here: https://github.com/madler/zlib/issues/171
                    //
                    // So, if the server requested for server_max_window_bits=8, we are
                    // going to use server_max_window_bits=9 instead and notify this in
                    // our negotiation response too.
                    deflaterMaxWindowBits = mwBits == 8 ? 9 : mwBits
                }
            }

            // If we received a valid client_max_window_bits value, use it to configure the inflater
            if parameter.hasPrefix("client_max_window_bits") {
                let maxWindowBits = parameter.components(separatedBy: "=")
                guard maxWindowBits.count == 2 else { continue }
                guard let mwBits = Int32(maxWindowBits[1]) else { continue }
                if mwBits >= 8 && mwBits <= 15  {
                    inflaterMaxWindowBits = mwBits
                }
            }

            if parameter.hasPrefix("client_no_context_takeover") {
                clientNoContextTakeover = true
            }

            if parameter.hasPrefix("server_no_context_takeover") {
                serverNoContextTakeover = true
            }
        }
        return [PermessageDeflateCompressor(maxWindowBits: deflaterMaxWindowBits, noContextTakeOver: serverNoContextTakeover),
                   PermessageDeflateDecompressor(maxWindowBits: inflaterMaxWindowBits, noContextTakeOver: clientNoContextTakeover)]
    }

    // Comprehend the Sec-WebSocket-Extensions request header and build a response header
    // In this context, the specification is not really very strict.
    func negotiate(header: String) -> String {
        var response = "permessage-deflate"

        // This shouldn't be really possible. We reached here only because the header was used to fetch the PerMessageDeflate implementation.
        guard header.hasPrefix("permessage-deflate") else { return response }

        for parameter in header.components(separatedBy: "; ") {
            if parameter == "client_no_context_takeover" {
                response.append("; client_no_context_takeover")
            }

            if parameter == "server_no_context_takeover" {
                response.append("; server_no_context_takeover")
            }

            // If we receive a valid value for server_max_window_bits, we accept it and return if
            // in the response. If we receive an invalid value, we default to 15 and return the
            // same in the response. If we receive no value, we ignore this header.
            if parameter.hasPrefix("server_max_window_bits") {
                let maxWindowBits = parameter.components(separatedBy: "=")
                guard maxWindowBits.count == 2 else { continue }
                guard let mwBits = Int32(maxWindowBits[1]) else { continue }
                if mwBits >= 8 && mwBits <= 15 {
                    // We received a valid value. However there's a special case here:
                    //
                    // There's an open zlib issue which does not set the window size
                    // to 256 (windowBits=8). For windowBits=8, zlib silently changes the
                    // value to 9. However, this apparent hack works only with zlib streams.
                    // WebSockets use raw deflate streams. For raw deflate streams, zlib has been
                    // patched to ignore the windowBits value 8.
                    // More details here: https://github.com/madler/zlib/issues/171
                    //
                    // So, if the server requested for server_max_window_bits=8, we are
                    // going to use server_max_window_bits=9 instead and notify this in
                    // our negotiation response too.
                    if mwBits == 8 {
                        response.append("; server_max_window_bits=9")
                    } else {
                        response.append("; \(parameter)")
                    }
                } else {
                    // we received an invalid value
                    response.append("; server_max_window_bits=15")
                }
            }
        }
        return response
    }
}
