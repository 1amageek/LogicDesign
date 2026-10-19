import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicDiagnostic: Codable {
    private enum CodingKeys: String, CodingKey { case `severity`, `code`, `message`, `entity`, `location`, `suggestedActions` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let severity = try container.decode(DiagnosticSeverity.self, forKey: .`severity`)
        let code = try container.decode(String.self, forKey: .`code`)
        let message = try container.decode(String.self, forKey: .`message`)
        let entity = try container.decodeIfPresent(String.self, forKey: .`entity`)
        let location = try container.decodeIfPresent(LogicSourceSpan.self, forKey: .`location`)
        let suggestedActions = try container.decode([String].self, forKey: .`suggestedActions`)
        self.init(severity: severity, code: code, message: message, entity: entity, location: location, suggestedActions: suggestedActions)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(severity, forKey: .`severity`)
        try container.encode(code, forKey: .`code`)
        try container.encode(message, forKey: .`message`)
        try container.encodeIfPresent(entity, forKey: .`entity`)
        try container.encodeIfPresent(location, forKey: .`location`)
        try container.encode(suggestedActions, forKey: .`suggestedActions`)
    }
}
