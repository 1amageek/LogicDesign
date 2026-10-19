import CircuiteFoundation

public struct LogicKernelSourceRange: Sendable, Equatable {
    public let artifactID: ArtifactID
    public let byteRange: Range<UInt64>

    public init(artifactID: ArtifactID, byteRange: Range<UInt64>) throws(LogicKernelError) {
        guard byteRange.upperBound <= artifactID.byteCount else {
            throw .invalidInput("Source range exceeds its exact artifact")
        }
        self.artifactID = artifactID
        self.byteRange = byteRange
    }
}
