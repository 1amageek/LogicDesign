import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicValidationResult: Codable {
    private enum CodingKeys: String, CodingKey { case `isValid`, `diagnostics` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let isValid = try container.decode(Bool.self, forKey: .`isValid`)
        let diagnostics = try container.decode([LogicDiagnostic].self, forKey: .`diagnostics`)
        self.init(isValid: isValid, diagnostics: diagnostics)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isValid, forKey: .`isValid`)
        try container.encode(diagnostics, forKey: .`diagnostics`)
    }
}
