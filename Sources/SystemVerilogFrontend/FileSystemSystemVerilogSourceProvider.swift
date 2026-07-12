import Foundation
import XcircuitePackage

public struct FileSystemSystemVerilogSourceProvider: SystemVerilogSourceProviding {
    public var root: URL

    public init(root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) {
        self.root = root
    }

    public func load(_ reference: XcircuiteFileReference) throws -> SystemVerilogSourceUnit {
        let url = root.appending(path: reference.path).standardizedFileURL
        guard url.path.hasPrefix(root.standardizedFileURL.path + "/") else {
            throw SystemVerilogSourceProviderError.invalidPath(reference.path)
        }
        let source: String
        do {
            source = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw SystemVerilogSourceProviderError.readFailed(path: reference.path, message: error.localizedDescription)
        }
        return SystemVerilogSourceUnit(path: reference.path, source: source)
    }
}
