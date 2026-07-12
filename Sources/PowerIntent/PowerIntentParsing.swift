import Foundation
import XcircuitePackage

public protocol PowerIntentParsing: Sendable {
    func execute(
        _ request: PowerIntentParsingRequest
    ) async throws -> XcircuiteEngineResultEnvelope<PowerIntentParsingPayload>
}
