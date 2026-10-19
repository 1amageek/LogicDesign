import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicDesignReference: Codable {
    private enum CodingKeys: String, CodingKey { case `artifact`, `topDesignName`, `designDigest`, `provenance` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let artifact = try container.decode(ArtifactReference.self, forKey: .`artifact`)
        let topDesignName = try container.decode(String.self, forKey: .`topDesignName`)
        let designDigest = try container.decode(String.self, forKey: .`designDigest`)
        let provenance = try container.decodeIfPresent(LogicDesignProvenance.self, forKey: .`provenance`)
        self.init(artifact: artifact, topDesignName: topDesignName, designDigest: designDigest, provenance: provenance)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(artifact, forKey: .`artifact`)
        try container.encode(topDesignName, forKey: .`topDesignName`)
        try container.encode(designDigest, forKey: .`designDigest`)
        try container.encodeIfPresent(provenance, forKey: .`provenance`)
    }
}
