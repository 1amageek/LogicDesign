import CryptoKit
import Foundation

/// Deterministic source-content digest operations used by the logic IR.
public enum LogicSourceDigest {
    public static func sha256HexadecimalValue(of data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
