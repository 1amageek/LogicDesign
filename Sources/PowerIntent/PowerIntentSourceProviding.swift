import Foundation
import CircuiteFoundation
import LogicIR
import LogicDesignSerialization

public protocol PowerIntentSourceProviding: Sendable {
    func load(_ input: LogicArtifactInput, format: PowerIntentFormat) throws -> PowerIntentSourceUnit
}
