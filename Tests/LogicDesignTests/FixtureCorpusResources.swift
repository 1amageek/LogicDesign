import Foundation

enum FixtureCorpusResources: Sendable {
    enum ResourceError: Error, Sendable, Equatable, LocalizedError {
        case missingResourceRoot
        case invalidPath(String)
        case missingResource(String)
        case unreadableResource(path: String, reason: String)
        case invalidUTF8(String)

        var errorDescription: String? {
            switch self {
            case .missingResourceRoot:
                "The LogicDesign fixture resource root is missing."
            case .invalidPath(let path):
                "The LogicDesign fixture path is invalid: \(path)"
            case .missingResource(let path):
                "The LogicDesign fixture resource is missing: \(path)"
            case .unreadableResource(let path, let reason):
                "The LogicDesign fixture resource could not be read at \(path): \(reason)"
            case .invalidUTF8(let path):
                "The LogicDesign fixture resource is not valid UTF-8: \(path)"
            }
        }
    }

    static func data(at path: String) throws -> Data {
        let resourceURL = try url(for: path)
        do {
            return try Data(contentsOf: resourceURL)
        } catch {
            throw ResourceError.unreadableResource(
                path: path,
                reason: String(describing: error)
            )
        }
    }

    static func string(at path: String) throws -> String {
        let resourceData = try data(at: path)
        guard let value = String(data: resourceData, encoding: .utf8) else {
            throw ResourceError.invalidUTF8(path)
        }
        return value
    }

    private static func url(for path: String) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.first == "Fixtures",
              components.count > 1,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ResourceError.invalidPath(path)
        }
        guard let resourceRoot = Bundle.module.resourceURL else {
            throw ResourceError.missingResourceRoot
        }

        let root = resourceRoot.standardizedFileURL
        let resourceURL = components.reduce(root) { partialURL, component in
            partialURL.appending(path: String(component))
        }.standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard resourceURL.path.hasPrefix(rootPrefix) else {
            throw ResourceError.invalidPath(path)
        }
        guard FileManager.default.fileExists(atPath: resourceURL.path) else {
            throw ResourceError.missingResource(path)
        }
        return resourceURL
    }
}
