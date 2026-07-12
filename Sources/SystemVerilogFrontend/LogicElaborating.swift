import Foundation
import XcircuitePackage
import LogicIR

public protocol LogicElaborating: Sendable {
    func execute(
        _ request: LogicElaborationRequest
    ) async throws -> XcircuiteEngineResultEnvelope<LogicElaborationPayload>
}
