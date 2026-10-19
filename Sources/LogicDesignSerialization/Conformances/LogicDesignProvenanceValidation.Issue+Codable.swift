import Foundation
import LogicIR

extension LogicDesignProvenanceValidation.Issue: Codable {
    private enum CaseKey: String, CodingKey { case `missing`, `invalid`, `inputDesignDigestMismatch`, `designDigestMissing` }
    private enum PayloadKey: String, CodingKey { case `expected`, `actual` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CaseKey.self)
        guard container.allKeys.count == 1, let selected = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected one enum case"))
        }
        switch selected {
        case .`missing`:
            _ = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`missing`)
            self = .missing
        case .`invalid`:
            _ = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`invalid`)
            self = .invalid
        case .`inputDesignDigestMismatch`:
            let payload = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`inputDesignDigestMismatch`)
            self = .inputDesignDigestMismatch(expected: try payload.decode(String.self, forKey: .`expected`), actual: try payload.decode(String.self, forKey: .`actual`))
        case .`designDigestMissing`:
            _ = try container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`designDigestMissing`)
            self = .designDigestMissing
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CaseKey.self)
        switch self {
        case .missing:
            let payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`missing`)
            _ = payload
        case .invalid:
            let payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`invalid`)
            _ = payload
        case .inputDesignDigestMismatch(let value0, let value1):
            var payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`inputDesignDigestMismatch`)
            try payload.encode(value0, forKey: .`expected`)
            try payload.encode(value1, forKey: .`actual`)
        case .designDigestMissing:
            let payload = container.nestedContainer(keyedBy: PayloadKey.self, forKey: .`designDigestMissing`)
            _ = payload
        }
    }
}
