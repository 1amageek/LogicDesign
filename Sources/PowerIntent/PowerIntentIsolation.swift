import Foundation
import LogicIR

public struct PowerIntentIsolation: Sendable, Hashable, Codable {
    public var id: String
    public var name: String
    public var domain: String
    public var appliesTo: String
    public var clampValue: String
    public var isolationSignal: String?
    public var source: LogicSourceSpan?

    public init(
        id: String,
        name: String,
        domain: String,
        appliesTo: String = "all",
        clampValue: String = "0",
        isolationSignal: String? = nil,
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.name = name
        self.domain = domain
        self.appliesTo = appliesTo
        self.clampValue = clampValue
        self.isolationSignal = isolationSignal
        self.source = source
    }
}
