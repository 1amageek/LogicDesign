import Foundation
import LogicIR

public struct PowerIntentRetention: Sendable, Hashable, Codable {
    public var id: String
    public var name: String
    public var domain: String
    public var retentionRegister: String?
    public var saveSignal: String?
    public var restoreSignal: String?
    public var source: LogicSourceSpan?

    public init(
        id: String,
        name: String,
        domain: String,
        retentionRegister: String? = nil,
        saveSignal: String? = nil,
        restoreSignal: String? = nil,
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.name = name
        self.domain = domain
        self.retentionRegister = retentionRegister
        self.saveSignal = saveSignal
        self.restoreSignal = restoreSignal
        self.source = source
    }
}
