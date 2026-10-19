public struct RTLGenerateBlock: Sendable, Hashable {
    public var id: String
    public var label: String
    public var kind: RTLGenerateKind
    public var condition: RTLExpression?
    public var loopVariable: String
    public var start: Int64
    public var limit: Int64
    public var step: Int64
    public var startExpression: RTLExpression?
    public var limitExpression: RTLExpression?
    public var stepExpression: RTLExpression?
    public var instances: [RTLInstance]
    public var assignments: [RTLAssignment]
    public var source: LogicSourceSpan?

    public init(
        id: String,
        label: String,
        kind: RTLGenerateKind = .forLoop,
        condition: RTLExpression? = nil,
        loopVariable: String,
        start: Int64,
        limit: Int64,
        step: Int64 = 1,
        startExpression: RTLExpression? = nil,
        limitExpression: RTLExpression? = nil,
        stepExpression: RTLExpression? = nil,
        instances: [RTLInstance] = [],
        assignments: [RTLAssignment] = [],
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.condition = condition
        self.loopVariable = loopVariable
        self.start = start
        self.limit = limit
        self.step = step
        self.startExpression = startExpression
        self.limitExpression = limitExpression
        self.stepExpression = stepExpression
        self.instances = instances
        self.assignments = assignments
        self.source = source
    }
}
