import Foundation
import XcircuitePackage

public struct FileSystemPowerIntentSourceProvider: PowerIntentSourceProviding {
    public var root: URL

    public init(root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) {
        self.root = root
    }

    public func load(_ reference: XcircuiteFileReference, format: PowerIntentFormat) throws -> PowerIntentSourceUnit {
        let url = root.appending(path: reference.path).standardizedFileURL
        guard url.path.hasPrefix(root.standardizedFileURL.path + "/") else {
            throw PowerIntentSourceProviderError.invalidPath(reference.path)
        }
        let source: String
        do {
            source = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw PowerIntentSourceProviderError.readFailed(path: reference.path, message: error.localizedDescription)
        }
        return PowerIntentSourceUnit(path: reference.path, source: source, format: format)
    }
}
