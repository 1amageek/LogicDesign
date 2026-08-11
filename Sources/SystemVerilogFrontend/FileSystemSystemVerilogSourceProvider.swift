import Foundation
import CircuiteFoundation
import LogicIR

public struct FileSystemSystemVerilogSourceProvider: SystemVerilogSourceProviding {
    public var root: URL

    public init(root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) {
        self.root = root
    }

    public func load(_ input: LogicArtifactInput) throws -> SystemVerilogSourceUnit {
        let path = input.path
        let url = root.appending(path: path).standardizedFileURL
        guard url.path.hasPrefix(root.standardizedFileURL.path + "/") else {
            throw SystemVerilogSourceProviderError.invalidPath(path)
        }
        let source: String
        do {
            source = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw SystemVerilogSourceProviderError.readFailed(path: path, message: error.localizedDescription)
        }
        return SystemVerilogSourceUnit(path: path, source: source)
    }
}
