import Foundation
import CircuiteFoundation

public struct FileSystemPowerIntentSourceProvider: PowerIntentSourceProviding {
    public var root: URL

    public init(root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) {
        self.root = root
    }

    public func load(_ reference: ArtifactLocator, format: PowerIntentFormat) throws -> PowerIntentSourceUnit {
        let path = reference.location.value
        let url = root.appending(path: path).standardizedFileURL
        guard url.path.hasPrefix(root.standardizedFileURL.path + "/") else {
            throw PowerIntentSourceProviderError.invalidPath(path)
        }
        let source: String
        do {
            source = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw PowerIntentSourceProviderError.readFailed(path: path, message: error.localizedDescription)
        }
        return PowerIntentSourceUnit(path: path, source: source, format: format)
    }
}
