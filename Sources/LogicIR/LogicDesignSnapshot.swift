import Foundation

public struct LogicDesignSnapshot: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var rtl: RTLDesign
    public var gate: GateDesign?
    public var designDigest: String?

    public init(
        rtl: RTLDesign,
        gate: GateDesign? = nil,
        designDigest: String? = nil,
        schemaVersion: Int = LogicDesignSnapshot.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.rtl = rtl
        self.gate = gate
        self.designDigest = designDigest
    }
}
