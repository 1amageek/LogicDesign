public struct LogicBitVector: Sendable, Hashable, Codable {
    public let width: Int
    public let bytes: [UInt8]

    public init(width: Int, bytes: [UInt8]) throws {
        guard width > 0 else {
            throw LogicBitVectorError.invalidWidth(width)
        }
        let requiredByteCount = (width + 7) / 8
        guard bytes.count == requiredByteCount else {
            throw LogicBitVectorError.invalidByteCount(
                expected: requiredByteCount,
                actual: bytes.count
            )
        }
        let unusedBitCount = requiredByteCount * 8 - width
        if unusedBitCount > 0 {
            let validMask = UInt8.max >> UInt8(unusedBitCount)
            guard bytes[0] & ~validMask == 0 else {
                throw LogicBitVectorError.valueExceedsWidth(width)
            }
        }
        self.width = width
        self.bytes = bytes
    }

    public init(width: Int, literalText: String) throws {
        guard width > 0 else {
            throw LogicBitVectorError.invalidWidth(width)
        }
        let normalizedText = literalText.replacingOccurrences(of: "_", with: "")
        let isNegative = normalizedText.hasPrefix("-")
        let magnitudeText = isNegative ? String(normalizedText.dropFirst()) : normalizedText
        let radix: UInt16
        let digits: Substring
        if magnitudeText.hasPrefix("0x") || magnitudeText.hasPrefix("0X") {
            radix = 16
            digits = magnitudeText.dropFirst(2)
        } else if magnitudeText.hasPrefix("0b") || magnitudeText.hasPrefix("0B") {
            radix = 2
            digits = magnitudeText.dropFirst(2)
        } else {
            radix = 10
            digits = magnitudeText[...]
        }
        guard !digits.isEmpty else {
            throw LogicBitVectorError.invalidLiteral(literalText)
        }
        let byteCount = (width + 7) / 8
        var littleEndian = [UInt8](repeating: 0, count: byteCount)
        for character in digits {
            guard let digit = character.hexDigitValue, digit < Int(radix) else {
                throw LogicBitVectorError.invalidLiteral(literalText)
            }
            var carry = UInt16(digit)
            for index in littleEndian.indices {
                let expanded = UInt16(littleEndian[index]) * radix + carry
                littleEndian[index] = UInt8(expanded & 0xff)
                carry = expanded >> 8
            }
            guard carry == 0 else {
                throw LogicBitVectorError.valueExceedsWidth(width)
            }
        }
        if isNegative {
            let signLimitIndex = (width - 1) / 8
            let signLimitMask = UInt8(1) << UInt8((width - 1) % 8)
            let exceedsSignedRange = littleEndian.indices.contains { index in
                if index > signLimitIndex {
                    return littleEndian[index] != 0
                }
                if index == signLimitIndex {
                    return littleEndian[index] > signLimitMask
                }
                return false
            } || (littleEndian[signLimitIndex] == signLimitMask
                  && littleEndian[..<signLimitIndex].contains { $0 != 0 })
            guard !exceedsSignedRange else {
                throw LogicBitVectorError.valueExceedsWidth(width)
            }
            for index in littleEndian.indices {
                littleEndian[index] = ~littleEndian[index]
            }
            var carry: UInt16 = 1
            for index in littleEndian.indices {
                let expanded = UInt16(littleEndian[index]) + carry
                littleEndian[index] = UInt8(expanded & 0xff)
                carry = expanded >> 8
            }
            let usedTopBits = width % 8
            if usedTopBits != 0 {
                littleEndian[byteCount - 1] &= UInt8.max >> UInt8(8 - usedTopBits)
            }
        }
        try self.init(width: width, bytes: littleEndian.reversed())
    }
}

public enum LogicBitVectorError: Error, Sendable, Equatable {
    case invalidWidth(Int)
    case invalidByteCount(expected: Int, actual: Int)
    case invalidLiteral(String)
    case valueExceedsWidth(Int)
}
