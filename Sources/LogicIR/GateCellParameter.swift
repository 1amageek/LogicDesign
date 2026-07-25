import Foundation

public struct GateCellParameter: Sendable, Hashable, Codable {
    public var name: String
    public var value: GateCellParameterValue

    public init(name: String, value: GateCellParameterValue) {
        self.name = name
        self.value = value
    }
}
