import Foundation
import XcircuitePackage

public protocol SystemVerilogSourceProviding: Sendable {
    func load(_ reference: XcircuiteFileReference) throws -> SystemVerilogSourceUnit
}
