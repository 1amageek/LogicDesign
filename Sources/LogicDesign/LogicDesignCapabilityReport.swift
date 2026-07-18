import Foundation

public struct LogicDesignCapabilityReport: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let packageName: String
    public let implementationVersion: String
    public let capabilities: [String]
    public let blockedSemantics: [String]
    public let validationChecks: [String]
    public let evidenceBoundary: LogicDesignEvidenceBoundary

    public init(
        packageName: String = "LogicDesign",
        implementationVersion: String = "1",
        capabilities: [String],
        blockedSemantics: [String],
        validationChecks: [String],
        evidenceBoundary: LogicDesignEvidenceBoundary
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.packageName = packageName
        self.implementationVersion = implementationVersion
        self.capabilities = capabilities
        self.blockedSemantics = blockedSemantics
        self.validationChecks = validationChecks
        self.evidenceBoundary = evidenceBoundary
    }

    public static let current = LogicDesignCapabilityReport(
        capabilities: [
            "stable_rtl_identity",
            "systemverilog_ansi_modules",
            "parameters_and_constant_expressions",
            "conditional_compilation_object_macros",
            "expression_and_function_like_preprocessor_macros",
            "continuous_assignments",
            "always_comb_always_ff_and_latch_assignments",
            "inferred_combinational_sensitivity",
            "connected_hierarchy_flattening",
            "parameterized_hierarchy_flattening",
            "hierarchical_inout_and_expression_outputs",
            "hierarchical_memory_flattening",
            "contextual_generate_elaboration",
            "constant_generate_else_if_elaboration",
            "symbolic_range_resolution",
            "rtl_snapshot_json_round_trip",
            "upf_power_domains_supply_sets_isolation_level_shifting_retention",
            "cpf_power_domain_policy_subset",
            "structured_diagnostics",
            "deterministic_json_cli"
        ],
        blockedSemantics: [
            "nonconstant_generate_constructs",
            "unresolved_hierarchy_parameters",
            "interfaces_programs_packages_classes",
            "concurrent_assertions",
            "full_upf_cpf_semantics"
        ],
        validationChecks: [
            "request_contract_validation",
            "snapshot_schema_and_digest_validation",
            "rtl_and_gate_structural_validation",
            "retained_native_fixture_corpus",
            "digest_bound_local_reference_correlation"
        ],
        evidenceBoundary: LogicDesignEvidenceBoundary(
            producedEvidence: [
                "canonical_logic_design_snapshots",
                "structured_diagnostics",
                "execution_provenance",
                "native_corpus_results",
                "local_reference_correlation"
            ],
            externalDecisions: [
                "external_tool_agreement",
                "process_scope_acceptance",
                "tool_trust_qualification",
                "release_authorization"
            ]
        )
    )

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case packageName
        case implementationVersion
        case capabilities
        case blockedSemantics
        case validationChecks
        case evidenceBoundary
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported LogicDesign capability report schema version \(schemaVersion)."
            )
        }
        self.schemaVersion = schemaVersion
        self.packageName = try container.decode(String.self, forKey: .packageName)
        self.implementationVersion = try container.decode(String.self, forKey: .implementationVersion)
        self.capabilities = try container.decode([String].self, forKey: .capabilities)
        self.blockedSemantics = try container.decode([String].self, forKey: .blockedSemantics)
        self.validationChecks = try container.decode([String].self, forKey: .validationChecks)
        self.evidenceBoundary = try container.decode(
            LogicDesignEvidenceBoundary.self,
            forKey: .evidenceBoundary
        )
    }
}
