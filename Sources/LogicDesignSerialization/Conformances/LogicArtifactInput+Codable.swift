import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicArtifactInput: Codable {
    private enum CodingKeys: String, CodingKey { case relativePath, descriptor, reference }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let relativePath = try container.decode(ArtifactRelativePath.self, forKey: .relativePath)
        let descriptor = try container.decode(ArtifactDescriptor.self, forKey: .descriptor)
        let reference = try container.decodeIfPresent(ArtifactReference.self, forKey: .reference)
        try self.init(path: relativePath.stringValue, kind: descriptor.kind,
                      format: descriptor.format, reference: reference)
        guard self.descriptor == descriptor else { throw LogicArtifactInputError.descriptorMismatch }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encode(descriptor, forKey: .descriptor)
        try container.encodeIfPresent(reference, forKey: .reference)
    }
}
