public protocol LogicDataflowValidating: Sendable {
    func validate(_ design: LogicDataflowDesign) -> LogicValidationResult
}
