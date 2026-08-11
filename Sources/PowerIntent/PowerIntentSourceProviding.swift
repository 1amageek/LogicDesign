import Foundation
import CircuiteFoundation
import LogicIR

public protocol PowerIntentSourceProviding: Sendable {
    func load(_ input: LogicArtifactInput, format: PowerIntentFormat) throws -> PowerIntentSourceUnit
}
