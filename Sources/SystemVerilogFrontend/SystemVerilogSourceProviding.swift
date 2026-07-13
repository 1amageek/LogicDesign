import Foundation
import CircuiteFoundation

public protocol SystemVerilogSourceProviding: Sendable {
    func load(_ reference: ArtifactLocator) throws -> SystemVerilogSourceUnit
}
