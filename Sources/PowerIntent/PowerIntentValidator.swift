import Foundation
import LogicIR

public struct PowerIntentValidator: Sendable {
    public init() {}

    public func validate(_ design: PowerIntentDesign) -> PowerIntentValidationResult {
        var diagnostics: [LogicDiagnostic] = []
        let domains = Set(design.domains.map(\.name))
        let supplySets = Set(design.supplySets.map(\.name))

        for domain in design.domains {
            if let supply = domain.primarySupplySet, !supplySets.contains(supply) {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "POWER_SUPPLY_SET_UNRESOLVED",
                    message: "Power domain references an undefined supply set or net.",
                    entity: "\(domain.name).\(supply)",
                    location: domain.source,
                    suggestedActions: ["define_supply_set", "correct_supply_reference"]
                ))
            }
        }
        for policy in design.isolationPolicies where !domains.contains(policy.domain) {
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "POWER_ISOLATION_DOMAIN_UNRESOLVED",
                message: "Isolation policy references an undefined power domain.",
                entity: policy.domain,
                location: policy.source,
                suggestedActions: ["define_power_domain", "correct_isolation_domain"]
            ))
        }
        for policy in design.retentionPolicies where !domains.contains(policy.domain) {
            diagnostics.append(LogicDiagnostic(
                severity: .error,
                code: "POWER_RETENTION_DOMAIN_UNRESOLVED",
                message: "Retention policy references an undefined power domain.",
                entity: policy.domain,
                location: policy.source,
                suggestedActions: ["define_power_domain", "correct_retention_domain"]
            ))
        }
        for policy in design.levelShifters {
            for domain in [policy.fromDomain, policy.toDomain].compactMap({ $0 }) where !domains.contains(domain) {
                diagnostics.append(LogicDiagnostic(
                    severity: .error,
                    code: "POWER_LEVEL_SHIFTER_DOMAIN_UNRESOLVED",
                    message: "Level-shifter policy references an undefined power domain.",
                    entity: domain,
                    location: policy.source,
                    suggestedActions: ["define_power_domain", "correct_level_shifter_domain"]
                ))
            }
        }
        return PowerIntentValidationResult(
            isValid: !diagnostics.contains { $0.severity == .error },
            diagnostics: diagnostics
        )
    }
}
