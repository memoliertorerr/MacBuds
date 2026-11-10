/// Real bytes from the owner's Buds2: docs/captures/2026-11-10-connect.txt.
/// One string per RFCOMM callback, exactly as delivered.
enum Capture {
    static let callbacks: [String] = [
        "FD 28 08 61 0A 03 37 60 01 00 11 00 00 03 BF 42 02 00 3A 01 3A 01 00 00 03 66 00 01 00 10 00 00 00 01 11 02 00 00 00 00 00 80 DD DD FD 06 54 C2 26 00 01 8B 7A DD",
        "FD 0D 88 63 00 00 01 81 01 01 81 01 00 00 53 B1 DD FD 29 D4 41 02 11 35 00 37 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 60 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 87 90 DD",
        "FD 06 14 C2 26 01 01 BA 49 DD",
        "FD 0D 40 27 01 5E 0A 06 43 10 42 4F 0F BF 43 F7 DD",
        "FD B8 80 40 14 46 42 44 41 00 FE 00 00 00 46 42 44 42 00 2B 00 00 00 46 42 44 43 00 4C 00 00 00 46 4C 44 41 00 59 00 00 00 46 4C 44 42 00 15 00 00 00 46 4C 44 43 00 06 00 00 00 46 52 44 41 00 FF 00 00 00 46 52 44 42 00 42 00 00 00 46 52 44 43 00 07 00 00 00 4E 42 44 41 00 FE 00 00 00 4E 42 44 42 00 FE 00 00 00 4E 42 44 43 00 A7 00 00 00 41 42 44 41 00 FE 00 00 00 41 42 44 42 00 FE 00 00 00 41 42 44 43 00 86 00 00 00 57 4C 4F 44 00 82 00 00 00 57 52 4F 44 00 FF 00 00 00 57 41 4C 44 00 FE 00 00 00 42 53 43 4C 00 22 47 00 00 42 53 43 52 00 79 47 00 00 0A D5 DD",
        "FD 0D C0 27 01 9E 0A 06 43 10 42 4F 0F BF 28 17 DD",
        "FD 1F 00 F4 01 00 00 00 11 5E 29 22 3C 24 23 47 01 F5 14 1B 00 00 07 04 00 00 01 00 5E 00 00 00 61 70 DD",
        "FD 1F 40 F4 4C 08 00 00 60 60 A1 23 35 25 24 9E FF F9 0F 1B 2D 00 05 04 00 00 01 00 5E 00 00 00 71 12 DD",
        "FD 1F 80 F4 01 00 00 00 11 1B CA 0A 00 00 1D 48 01 23 10 0A 00 00 07 04 00 00 01 00 1B 00 00 00 19 46 DD",
        "FD 1F C0 F4 4E 08 00 00 60 37 89 15 00 00 25 74 FF DC 0E 0A 2D 00 07 04 00 00 02 00 1B 00 00 00 6D E2 DD",
        "FD 22 00 F2 4C 4C 7C 20 00 C1 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 30 00 01 00 92 0A DD",
        "FD 22 40 F2 52 15 7B 20 00 C1 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 30 00 01 00 36 09 DD",
    ]

    /// Message IDs of the 14 frames, in order.
    static let frameIDs: [UInt8] = [
        0x61, 0xC2, 0x63, 0x41, 0xC2, 0x27, 0x40, 0x27, 0xF4, 0xF4, 0xF4, 0xF4, 0xF2, 0xF2,
    ]

    static var chunks: [[UInt8]] { callbacks.map(hex) }
    static var extendedStatusFrame: [UInt8] { Array(chunks[0].prefix(44)) }
}

func hex(_ string: String) -> [UInt8] {
    string.split(separator: " ").map { UInt8($0, radix: 16)! }
}
