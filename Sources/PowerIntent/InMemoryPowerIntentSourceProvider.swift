import Foundation
import CircuiteFoundation
import LogicIR

public struct InMemoryPowerIntentSourceProvider: PowerIntentSourceProviding {
    public var sources: [String: String]

    public init(sources: [String: String]) {
        self.sources = sources
    }

    public func load(_ input: LogicArtifactInput, format: PowerIntentFormat) throws -> PowerIntentSourceUnit {
        let path = input.path
        guard let source = sources[path] else {
            throw PowerIntentSourceProviderError.readFailed(
                path: path,
                message: "No source was registered for the referenced path."
            )
        }
        return PowerIntentSourceUnit(path: path, source: source, format: format)
    }
}
