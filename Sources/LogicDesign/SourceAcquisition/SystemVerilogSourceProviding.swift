import Foundation
import CircuiteFoundation
import LogicIR
import LogicDesignSerialization

public protocol SystemVerilogSourceProviding: Sendable {
    func load(_ input: LogicArtifactInput) throws -> SystemVerilogSourceUnit
}
