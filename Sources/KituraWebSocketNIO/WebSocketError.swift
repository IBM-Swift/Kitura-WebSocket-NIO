import Foundation

/// An error enum used when throwing errors within KituraWebSocket.
public enum WebSocketError: Error {
    
    /// An invalid opcode was received in a WebSocket frame
    case invalidOpCode(UInt8)
    
    /// A frame was received that had an unmasked payload
    case unmaskedFrame
}


extension WebSocketError: CustomStringConvertible {
    /// Generate a printable version of this enum.
    public var description: String {
        switch self {
        case .invalidOpCode(let opCode):
            return "Parsed a frame with an invalid operation code of \(opCode)"
        case .unmaskedFrame:
            return "Received a frame from a client that wasn't masked"
        }
    }
}
