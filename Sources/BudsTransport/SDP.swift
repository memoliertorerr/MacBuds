import Foundation
@preconcurrency import IOBluetooth

extension IOBluetoothSDPServiceRecord {
    /// Service class UUIDs (SDP attribute 0x0001) as upper-case hex without dashes.
    var serviceClassUUIDs: [String] {
        guard let element = getAttributeDataElement(0x0001) else { return [] }
        var out: [String] = []
        Self.collectUUIDs(element, into: &out)
        return out
    }

    private static func collectUUIDs(_ element: IOBluetoothSDPDataElement, into out: inout [String]) {
        if element.getTypeDescriptor() == BluetoothSDPDataElementTypeDescriptor(kBluetoothSDPDataElementTypeUUID),
           let uuid = element.getUUIDValue() {
            let data = Data(bytes: uuid.bytes, count: uuid.length)
            out.append(data.map { String(format: "%02X", $0) }.joined())
        } else if let children = element.getArrayValue() {
            for case let child as IOBluetoothSDPDataElement in children {
                collectUUIDs(child, into: &out)
            }
        }
    }

    var rfcommChannel: UInt8? {
        var channel: BluetoothRFCOMMChannelID = 0
        return getRFCOMMChannelID(&channel) == kIOReturnSuccess ? channel : nil
    }
}

func ioReturnHex(_ r: IOReturn) -> String {
    String(format: "0x%08X", UInt32(bitPattern: r))
}

func hexBytes(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}
