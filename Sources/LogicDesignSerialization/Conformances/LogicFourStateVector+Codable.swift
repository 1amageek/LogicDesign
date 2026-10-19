import Foundation
import LogicIR

@available(macOS 26.0, *)
extension LogicFourStateVector: Codable {
    private enum CodingKeys: String, CodingKey { case schemaVersion, width, valueWords, unknownWords }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion) == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: container,
                                                  debugDescription: "Unsupported four-state vector schema")
        }
        let width = try LogicBitWidth(container.decode(Int.self, forKey: .width))
        let values = try container.decode([UInt64].self, forKey: .valueWords)
        let unknowns = try container.decode([UInt64].self, forKey: .unknownWords)
        try self.init(width: width, valueWords: values, unknownWords: unknowns)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .schemaVersion)
        try container.encode(width.value, forKey: .width)
        // Materialize only at the host serialization boundary.
        try withPlanes { values, unknowns in
            var valueWords: [UInt64] = []; valueWords.reserveCapacity(values.count)
            var unknownWords: [UInt64] = []; unknownWords.reserveCapacity(unknowns.count)
            for index in values.indices { valueWords.append(values[index]) }
            for index in unknowns.indices { unknownWords.append(unknowns[index]) }
            try container.encode(valueWords, forKey: .valueWords)
            try container.encode(unknownWords, forKey: .unknownWords)
        }
    }
}
