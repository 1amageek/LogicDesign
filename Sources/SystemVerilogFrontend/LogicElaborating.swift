import Foundation
import CircuiteFoundation
import LogicIR

public protocol LogicElaborating: Engine
where Request == LogicElaborationRequest, Output == LogicElaborationResult {}
