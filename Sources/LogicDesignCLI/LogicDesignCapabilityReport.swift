import Foundation

public struct LogicDesignCapabilityReport: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var package: String
    public var implementationVersion: String
    public var capabilities: [String]
    public var blockedSemantics: [String]
    public var qualification: String

    public init(
        schemaVersion: Int = 1,
        package: String = "LogicDesign",
        implementationVersion: String = "1",
        capabilities: [String],
        blockedSemantics: [String],
        qualification: String
    ) {
        self.schemaVersion = schemaVersion
        self.package = package
        self.implementationVersion = implementationVersion
        self.capabilities = capabilities
        self.blockedSemantics = blockedSemantics
        self.qualification = qualification
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
            "full_upf_cpf_semantics",
            "external_tool_correlation",
            "foundry_process_qualification"
        ],
        qualification: "smoke_checked_native_subset; no foundry or oracle qualification"
    )
}
