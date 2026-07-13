import Foundation
import CircuiteFoundation
import LogicIR

public protocol LogicElaborating: Sendable {
    func execute(
        _ request: LogicElaborationRequest
    ) async throws -> LogicElaborationResult
}
