import Foundation
import XcircuitePackage

public struct InMemorySystemVerilogSourceProvider: SystemVerilogSourceProviding {
    public var sources: [String: String]

    public init(sources: [String: String]) {
        self.sources = sources
    }

    public func load(_ reference: XcircuiteFileReference) throws -> SystemVerilogSourceUnit {
        guard let source = sources[reference.path] else {
            throw SystemVerilogSourceProviderError.readFailed(
                path: reference.path,
                message: "No source was registered for the referenced path."
            )
        }
        return SystemVerilogSourceUnit(path: reference.path, source: source)
    }
}
