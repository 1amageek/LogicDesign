import Foundation
import XcircuitePackage
import LogicIR

public struct LogicElaborationPayload: Sendable, Hashable, Codable {
    public var design: LogicDesignReference?
    public var snapshot: LogicDesignSnapshot?
    public var validation: LogicValidationResult?
    public var sourceUnitCount: Int

    public init(
        design: LogicDesignReference?,
        sourceUnitCount: Int,
        snapshot: LogicDesignSnapshot? = nil,
        validation: LogicValidationResult? = nil
    ) {
        self.design = design
        self.snapshot = snapshot
        self.validation = validation
        self.sourceUnitCount = sourceUnitCount
    }
}
