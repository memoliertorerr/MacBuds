/// Decoders for the read-only information replies. docs/PROTOCOL.md §4.10–4.11.

public enum FitResult: Sendable, Equatable, CustomStringConvertible {
    case poor, good, failed, unknown(UInt8)

    public init(byte: UInt8) {
        switch byte {
        case 0: self = .poor
        case 1: self = .good
        case 2: self = .failed
        default: self = .unknown(byte)
        }
    }

    public var description: String {
        switch self {
        case .poor: "poor fit"
        case .good: "good fit"
        case .failed: "test failed"
        case .unknown(let byte): "unknown result (\(byte))"
        }
    }
}

public enum DeviceInfo {
    /// Printable ASCII from a fixed-width field; padding and control bytes are dropped.
    public static func ascii<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        String(decoding: bytes.filter { (0x20...0x7E).contains($0) }, as: UTF8.self)
            .trimmingPrefixAndSuffixSpaces()
    }

    /// Splits a reply holding a left value then a right value, each `width` bytes. The right
    /// half may be missing.
    public static func leftRight(_ payload: [UInt8], width: Int) -> (left: String, right: String?) {
        let left = ascii(payload.prefix(width))
        let rest = payload.dropFirst(width).prefix(width)
        return (left, rest.isEmpty ? nil : ascii(rest))
    }
}

extension String {
    fileprivate func trimmingPrefixAndSuffixSpaces() -> String {
        var view = Substring(self)
        while view.first == " " { view.removeFirst() }
        while view.last == " " { view.removeLast() }
        return String(view)
    }
}
