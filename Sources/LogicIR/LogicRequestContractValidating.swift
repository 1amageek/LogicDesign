import Foundation
import CircuiteFoundation

public protocol LogicRequestContractValidating: Sendable {
    func validate(
        schemaVersion: Int,
        expectedSchemaVersion: Int,
        runID: String,
        inputs: [ArtifactLocator],
        topDesignName: String,
        inlineSourceCount: Int
    ) -> LogicValidationResult
}
