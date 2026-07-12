import Foundation

public struct LogicRange: Sendable, Hashable, Codable {
    public var msb: Int
    public var lsb: Int

    public init(msb: Int, lsb: Int) {
        self.msb = msb
        self.lsb = lsb
    }

    public var width: Int {
        abs(msb - lsb) + 1
    }
}
