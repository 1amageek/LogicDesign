import Foundation

public protocol LogicDesignValidating: Sendable {
    func validate(_ design: RTLDesign) -> LogicValidationResult
    func validate(_ design: GateDesign) -> LogicValidationResult
}
