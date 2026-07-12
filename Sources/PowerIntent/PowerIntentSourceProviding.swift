import Foundation
import XcircuitePackage

public protocol PowerIntentSourceProviding: Sendable {
    func load(_ reference: XcircuiteFileReference, format: PowerIntentFormat) throws -> PowerIntentSourceUnit
}
