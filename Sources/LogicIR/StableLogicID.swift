import Foundation
import CircuiteFoundation

public enum StableLogicID {
    public static func make(kind: String, path: String, name: String) -> String {
        let input = "\(kind)|\(path)|\(name)"
        let digest = LogicSourceDigest.sha256HexadecimalValue(of: Data(input.utf8))
        return "\(kind)_\(digest.prefix(16))"
    }
}
