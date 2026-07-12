import Foundation
import XcircuitePackage

public protocol LogicRequestContractValidating: Sendable {
    func validate(
        schemaVersion: Int,
        expectedSchemaVersion: Int,
        runID: String,
        inputs: [XcircuiteFileReference],
        topDesignName: String,
        inlineSourceCount: Int
    ) -> LogicValidationResult
}
