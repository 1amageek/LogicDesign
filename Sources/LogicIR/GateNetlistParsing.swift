import Foundation

public protocol GateNetlistParsing: Sendable {
    func parse(_ source: String, path: String, topDesignName: String) -> GateNetlistParseResult
}
