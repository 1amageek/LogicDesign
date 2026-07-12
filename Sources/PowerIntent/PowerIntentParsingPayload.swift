import Foundation
import XcircuitePackage
import LogicIR

public struct PowerIntentParsingPayload: Sendable, Hashable, Codable {
    public var reference: PowerIntentReference?
    public var domainCount: Int
    public var intent: PowerIntentDesign?
    public var validation: PowerIntentValidationResult?

    public init(
        reference: PowerIntentReference?,
        domainCount: Int,
        intent: PowerIntentDesign? = nil,
        validation: PowerIntentValidationResult? = nil
    ) {
        self.reference = reference
        self.domainCount = domainCount
        self.intent = intent
        self.validation = validation
    }
}
