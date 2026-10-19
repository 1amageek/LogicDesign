import Foundation
import LogicIR

public struct StableLogicID: LogicDraftIdentityGenerating {
    public init() {}

    public func make(kind: String, path: String, name: String) -> String {
        Self.make(kind: kind, path: path, name: name)
    }

    public static func make(kind: String, path: String, name: String) -> String {
        let input = "\(kind)|\(path)|\(name)"
        let digest = LogicSourceDigest.sha256HexadecimalValue(of: Data(input.utf8))
        return "\(kind)_\(digest.prefix(16))"
    }
}
