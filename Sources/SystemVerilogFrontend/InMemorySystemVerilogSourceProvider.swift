import Foundation
import CircuiteFoundation
import LogicIR

public struct InMemorySystemVerilogSourceProvider: SystemVerilogSourceProviding {
    public var sources: [String: String]

    public init(sources: [String: String]) {
        self.sources = sources
    }

    public func load(_ input: LogicArtifactInput) throws -> SystemVerilogSourceUnit {
        let path = input.path
        guard let source = sources[path] else {
            throw SystemVerilogSourceProviderError.readFailed(
                path: path,
                message: "No source was registered for the referenced path."
            )
        }
        return SystemVerilogSourceUnit(path: path, source: source)
    }
}
