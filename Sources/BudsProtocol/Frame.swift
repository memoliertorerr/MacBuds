/// One protocol message on the wire. See docs/PROTOCOL.md §2.
///
///     FD | header lo | header hi | message ID | payload… | CRC lo | CRC hi | DD
public struct Frame: Equatable, Sendable {
    public static let startMarker: UInt8 = 0xFD
    public static let endMarker: UInt8 = 0xDD
    /// Header bits 0–9: message ID + payload + CRC.
    static let lengthMask: UInt16 = 0x03FF
    /// SOM, two header bytes and EOM are not counted by the length field.
    static let overhead = 4
    /// Largest payload the 10-bit length field can describe.
    public static let maxPayload = Int(lengthMask) - 3

    public var id: UInt8
    public var payload: [UInt8]
    /// Header bits 10–15 as received: a rolling counter and flags whose meaning is not
    /// established. Kept for diagnostics only; frames we send leave them zero.
    public var headerFlags: UInt16

    public init(id: UInt8, payload: [UInt8] = [], headerFlags: UInt16 = 0) {
        self.id = id
        self.payload = payload
        self.headerFlags = headerFlags & ~Frame.lengthMask
    }

    public enum DecodeError: Error, Equatable {
        case tooShort
        case badStartMarker(UInt8)
        case lengthMismatch(declared: Int, actual: Int)
        case badEndMarker(UInt8)
        case crcMismatch(expected: UInt16, actual: UInt16)
    }

    public enum EncodeError: Error, Equatable {
        case payloadTooLong(Int)
    }

    public func encode() throws -> [UInt8] {
        guard payload.count <= Frame.maxPayload else {
            throw EncodeError.payloadTooLong(payload.count)
        }
        let header = UInt16(payload.count + 3) | headerFlags
        let crc = CRC16.xmodem([id] + payload)
        var out: [UInt8] = [Frame.startMarker, UInt8(header & 0xFF), UInt8(header >> 8), id]
        out += payload
        out += [UInt8(crc & 0xFF), UInt8(crc >> 8), Frame.endMarker]
        return out
    }

    /// Decodes exactly one complete frame.
    public init(decoding bytes: [UInt8]) throws {
        guard bytes.count >= 7 else { throw DecodeError.tooShort }
        guard bytes[0] == Frame.startMarker else { throw DecodeError.badStartMarker(bytes[0]) }
        let header = UInt16(bytes[1]) | UInt16(bytes[2]) << 8
        let length = Int(header & Frame.lengthMask)
        guard length >= 3, length + Frame.overhead == bytes.count else {
            throw DecodeError.lengthMismatch(declared: length, actual: bytes.count - Frame.overhead)
        }
        guard bytes[bytes.count - 1] == Frame.endMarker else {
            throw DecodeError.badEndMarker(bytes[bytes.count - 1])
        }
        let body = bytes[3..<(bytes.count - 3)]
        let wire = UInt16(bytes[bytes.count - 3]) | UInt16(bytes[bytes.count - 2]) << 8
        let computed = CRC16.xmodem(body)
        guard wire == computed else {
            throw DecodeError.crcMismatch(expected: computed, actual: wire)
        }
        self.init(id: bytes[3], payload: Array(body.dropFirst()), headerFlags: header)
    }
}

/// Turns the RFCOMM byte stream into frames. Feed it chunks exactly as they arrive: a chunk
/// may hold several frames, part of one, or noise.
///
/// Frames are delimited by the header length, never by scanning for the end marker — FD and
/// DD are ordinary values inside payloads and CRCs. On any malformed frame the decoder drops
/// the start byte and resynchronises on the next FD.
public struct FrameStreamDecoder: Sendable {
    private var buffer: [UInt8] = []
    /// Bytes discarded while resynchronising, for diagnostics.
    public private(set) var discardedByteCount = 0

    public init() {}

    public mutating func push<S: Sequence>(_ chunk: S) -> [Frame] where S.Element == UInt8 {
        buffer.append(contentsOf: chunk)
        var frames: [Frame] = []
        var cursor = 0

        while true {
            guard let start = buffer[cursor...].firstIndex(of: Frame.startMarker) else {
                discardedByteCount += buffer.count - cursor
                cursor = buffer.count
                break
            }
            discardedByteCount += start - cursor
            cursor = start
            guard buffer.count - cursor >= 3 else { break }

            let header = UInt16(buffer[cursor + 1]) | UInt16(buffer[cursor + 2]) << 8
            let length = Int(header & Frame.lengthMask)
            guard length >= 3 else {
                cursor += 1
                discardedByteCount += 1
                continue
            }
            let total = length + Frame.overhead
            guard buffer.count - cursor >= total else { break }

            if let frame = try? Frame(decoding: Array(buffer[cursor..<(cursor + total)])) {
                frames.append(frame)
                cursor += total
            } else {
                cursor += 1
                discardedByteCount += 1
            }
        }

        buffer.removeFirst(cursor)
        return frames
    }

    public mutating func reset() {
        buffer.removeAll()
    }
}
