import Foundation

/// Preserves the symbolic bounds used to declare a vector or memory range.
public struct RTLRangeExpression: Sendable, Hashable, Codable {
    public var msb: RTLExpression
    public var lsb: RTLExpression

    public init(msb: RTLExpression, lsb: RTLExpression) {
        self.msb = msb
        self.lsb = lsb
    }
}
