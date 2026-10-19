import Foundation
import CircuiteFoundation
import LogicIR
import LogicDesignSerialization

public protocol LogicElaborating: Engine
where Request == LogicElaborationRequest, Output == LogicElaborationResult {}
