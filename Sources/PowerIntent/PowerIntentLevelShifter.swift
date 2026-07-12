import Foundation
import LogicIR

public struct PowerIntentLevelShifter: Sendable, Hashable, Codable {
    public var id: String
    public var name: String
    public var fromDomain: String?
    public var toDomain: String?
    public var appliesTo: String
    public var source: LogicSourceSpan?

    public init(
        id: String,
        name: String,
        fromDomain: String? = nil,
        toDomain: String? = nil,
        appliesTo: String = "all",
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.name = name
        self.fromDomain = fromDomain
        self.toDomain = toDomain
        self.appliesTo = appliesTo
        self.source = source
    }
}
