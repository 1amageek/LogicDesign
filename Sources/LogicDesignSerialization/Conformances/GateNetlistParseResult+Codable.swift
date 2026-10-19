import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension GateNetlistParseResult: Codable {
    private enum CodingKeys: String, CodingKey { case `design`, `diagnostics` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let design = try container.decodeIfPresent(GateDesign.self, forKey: .`design`)
        let diagnostics = try container.decode([LogicDiagnostic].self, forKey: .`diagnostics`)
        self.init(design: design, diagnostics: diagnostics)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(design, forKey: .`design`)
        try container.encode(diagnostics, forKey: .`diagnostics`)
    }
}
