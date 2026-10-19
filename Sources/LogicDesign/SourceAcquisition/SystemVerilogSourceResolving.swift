import Foundation

public protocol SystemVerilogSourceResolving: Sendable {
    func resolve(_ sources: [SystemVerilogSourceUnit]) throws -> [SystemVerilogSourceUnit]
}
