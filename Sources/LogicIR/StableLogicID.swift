import Foundation
import CircuiteFoundation

public enum StableLogicID {
    public static func make(kind: String, path: String, name: String) -> String {
        let input = "\(kind)|\(path)|\(name)"
        do {
            let digest = try SHA256ContentDigester().digest(data: Data(input.utf8))
            return "\(kind)_\(digest.hexadecimalValue.prefix(16))"
        } catch {
            preconditionFailure("Unable to compute stable logic identifier: \(error)")
        }
    }
}
