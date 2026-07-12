import Foundation
import XcircuitePackage

public struct InMemoryPowerIntentSourceProvider: PowerIntentSourceProviding {
    public var sources: [String: String]

    public init(sources: [String: String]) {
        self.sources = sources
    }

    public func load(_ reference: XcircuiteFileReference, format: PowerIntentFormat) throws -> PowerIntentSourceUnit {
        guard let source = sources[reference.path] else {
            throw PowerIntentSourceProviderError.readFailed(
                path: reference.path,
                message: "No source was registered for the referenced path."
            )
        }
        return PowerIntentSourceUnit(path: reference.path, source: source, format: format)
    }
}
