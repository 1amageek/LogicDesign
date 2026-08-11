import Foundation
import CircuiteFoundation
import LogicIR

public protocol SystemVerilogSourceProviding: Sendable {
    func load(_ input: LogicArtifactInput) throws -> SystemVerilogSourceUnit
}
