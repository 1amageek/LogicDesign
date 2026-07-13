import Foundation
import CircuiteFoundation

public protocol PowerIntentParsing: Sendable {
    func execute(
        _ request: PowerIntentParsingRequest
    ) async throws -> PowerIntentParsingResult
}
