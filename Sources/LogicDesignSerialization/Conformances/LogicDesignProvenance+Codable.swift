import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicDesignProvenance: Codable {
    private enum CodingKeys: String, CodingKey { case `schemaVersion`, `sourceDesignDigest`, `inputDesignDigest`, `transformationID`, `producerID`, `producerVersion`, `runID` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .`schemaVersion`)
        let sourceDesignDigest = try container.decode(String.self, forKey: .`sourceDesignDigest`)
        let inputDesignDigest = try container.decodeIfPresent(String.self, forKey: .`inputDesignDigest`)
        let transformationID = try container.decodeIfPresent(String.self, forKey: .`transformationID`)
        let producerID = try container.decode(String.self, forKey: .`producerID`)
        let producerVersion = try container.decode(String.self, forKey: .`producerVersion`)
        let runID = try container.decodeIfPresent(String.self, forKey: .`runID`)
        self.init(sourceDesignDigest: sourceDesignDigest, inputDesignDigest: inputDesignDigest, transformationID: transformationID, producerID: producerID, producerVersion: producerVersion, runID: runID, schemaVersion: schemaVersion)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .`schemaVersion`)
        try container.encode(sourceDesignDigest, forKey: .`sourceDesignDigest`)
        try container.encodeIfPresent(inputDesignDigest, forKey: .`inputDesignDigest`)
        try container.encodeIfPresent(transformationID, forKey: .`transformationID`)
        try container.encode(producerID, forKey: .`producerID`)
        try container.encode(producerVersion, forKey: .`producerVersion`)
        try container.encodeIfPresent(runID, forKey: .`runID`)
    }
}
