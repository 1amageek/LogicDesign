import CircuiteFoundation

/// Convenience construction for planned logic-design inputs.
public extension ArtifactLocator {
    init(path: String, kind: ArtifactKind, format: ArtifactFormat) throws {
        self.init(
            location: try ArtifactLocation(workspaceRelativePath: path),
            role: .input,
            kind: kind,
            format: format
        )
    }
}
