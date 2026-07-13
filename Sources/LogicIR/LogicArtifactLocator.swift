import CircuiteFoundation

/// Convenience construction for planned logic-design inputs.
public extension ArtifactLocator {
    init(path: String, kind: ArtifactKind, format: ArtifactFormat) {
        do {
            try self.init(
                location: ArtifactLocation(workspaceRelativePath: path),
                role: .input,
                kind: kind,
                format: format
            )
        } catch {
            preconditionFailure("Invalid logic artifact locator: \(error)")
        }
    }
}
