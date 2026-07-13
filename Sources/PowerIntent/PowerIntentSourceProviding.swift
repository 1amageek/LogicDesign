import Foundation
import CircuiteFoundation

public protocol PowerIntentSourceProviding: Sendable {
    func load(_ reference: ArtifactLocator, format: PowerIntentFormat) throws -> PowerIntentSourceUnit
}
