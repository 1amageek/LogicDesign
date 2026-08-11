import CircuiteFoundation

public enum LogicArtifactInputError: Error, Sendable, Equatable {
    case descriptorMismatch
}

public struct LogicArtifactInput: Sendable, Hashable, Codable {
    public let relativePath: ArtifactRelativePath
    public let descriptor: ArtifactDescriptor
    public let reference: ArtifactReference?

    public var path: String { relativePath.stringValue }
    public var kind: ArtifactKind { descriptor.kind }
    public var format: ArtifactFormat { descriptor.format }

    public init(
        path: String,
        kind: ArtifactKind,
        format: ArtifactFormat,
        reference: ArtifactReference? = nil
    ) throws {
        let descriptor = ArtifactDescriptor(role: .input, kind: kind, format: format)
        if let reference, reference.descriptor != descriptor {
            throw LogicArtifactInputError.descriptorMismatch
        }
        self.relativePath = try ArtifactRelativePath(
            segments: path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        )
        self.descriptor = descriptor
        self.reference = reference
    }
}
