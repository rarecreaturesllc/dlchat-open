import Foundation

/// A bit string, most significant bit first. Bits past `count` in the last
/// byte are always zero, so equal strings compare equal and MACs are stable.
public struct Bits: Equatable {
    public private(set) var bytes: [UInt8]
    public private(set) var count: Int

    public init() {
        bytes = []
        count = 0
    }

    /// The first `count` bits of `bytes`; the rest are dropped.
    public init(bytes: [UInt8], count: Int) {
        precondition(count >= 0 && count <= bytes.count * 8, "count exceeds bytes")
        self.bytes = Array(bytes.prefix((count + 7) / 8))
        self.count = count
        clearTail()
    }

    public mutating func append(_ value: UInt64, width: Int) {
        precondition(width >= 0 && width <= 64, "width out of range")
        for shift in stride(from: width - 1, through: 0, by: -1) {
            appendBit((value >> UInt64(shift)) & 1 == 1)
        }
    }

    public mutating func append(_ other: Bits) {
        for i in 0..<other.count { appendBit(other.bit(at: i)) }
    }

    public func bit(at index: Int) -> Bool {
        precondition(index >= 0 && index < count, "bit index out of range")
        return bytes[index / 8] & (0x80 >> UInt8(index % 8)) != 0
    }

    public mutating func flip(at index: Int) {
        precondition(index >= 0 && index < count, "bit index out of range")
        bytes[index / 8] ^= 0x80 >> UInt8(index % 8)
    }

    /// `width` bits starting at `start`, as an unsigned number.
    public func value(at start: Int, width: Int) -> UInt64 {
        precondition(width <= 64 && start >= 0 && start + width <= count, "range out of bounds")
        var result: UInt64 = 0
        for i in start..<(start + width) {
            result = (result << 1) | (bit(at: i) ? 1 : 0)
        }
        return result
    }

    public func slice(from start: Int, count length: Int) -> Bits {
        precondition(start >= 0 && length >= 0 && start + length <= count, "range out of bounds")
        var out = Bits()
        for i in start..<(start + length) { out.appendBit(bit(at: i)) }
        return out
    }

    private mutating func appendBit(_ on: Bool) {
        if count % 8 == 0 { bytes.append(0) }
        if on { bytes[count / 8] |= 0x80 >> UInt8(count % 8) }
        count += 1
    }

    private mutating func clearTail() {
        let spare = bytes.count * 8 - count
        if spare > 0 { bytes[bytes.count - 1] &= 0xFF << UInt8(spare) }
    }
}
