import Foundation
import XcircuitePackage

public enum StableLogicID {
    public static func make(kind: String, path: String, name: String) -> String {
        let input = "\(kind)|\(path)|\(name)"
        return "\(kind)_\(XcircuiteHasher().sha256(data: Data(input.utf8)).prefix(16))"
    }
}
