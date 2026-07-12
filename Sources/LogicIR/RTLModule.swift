import Foundation

public struct RTLModule: Sendable, Hashable, Codable {
    public var id: String
    public var name: String
    public var parameters: [RTLParameter]
    public var ports: [RTLPort]
    public var signals: [RTLSignal]
    public var memories: [RTLMemory]
    public var assignments: [RTLAssignment]
    public var processes: [RTLProcess]
    public var instances: [RTLInstance]
    public var generateBlocks: [RTLGenerateBlock]
    public var source: LogicSourceSpan?

    public init(
        id: String,
        name: String,
        parameters: [RTLParameter] = [],
        ports: [RTLPort] = [],
        signals: [RTLSignal] = [],
        memories: [RTLMemory] = [],
        assignments: [RTLAssignment] = [],
        processes: [RTLProcess] = [],
        instances: [RTLInstance] = [],
        generateBlocks: [RTLGenerateBlock] = [],
        source: LogicSourceSpan? = nil
    ) {
        self.id = id
        self.name = name
        self.parameters = parameters
        self.ports = ports
        self.signals = signals
        self.memories = memories
        self.assignments = assignments
        self.processes = processes
        self.instances = instances
        self.generateBlocks = generateBlocks
        self.source = source
    }
}
