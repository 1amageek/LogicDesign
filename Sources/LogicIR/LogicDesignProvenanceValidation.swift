import Foundation

public enum LogicDesignProvenanceValidation {
    public enum Issue: Sendable, Hashable, Codable {
        case missing
        case invalid
        case inputDesignDigestMismatch(expected: String, actual: String)
        case designDigestMissing

        public var code: String {
            switch self {
            case .missing: return "design_provenance_missing"
            case .invalid: return "design_provenance_invalid"
            case .inputDesignDigestMismatch: return "design_provenance_input_digest_mismatch"
            case .designDigestMissing: return "design_digest_missing"
            }
        }

        public var message: String {
            switch self {
            case .missing:
                return "Design lineage provenance is required for this handoff."
            case .invalid:
                return "Design lineage provenance failed schema and identity validation."
            case let .inputDesignDigestMismatch(expected, actual):
                return "Design lineage input digest \(actual) does not match the referenced design digest \(expected)."
            case .designDigestMissing:
                return "The referenced design digest is empty."
            }
        }

        public var diagnosticCode: String {
            code.uppercased()
        }
    }

    public static func issues(
        for reference: LogicDesignReference,
        requireProvenance: Bool = false
    ) -> [Issue] {
        issues(
            for: reference.designDigest,
            provenance: reference.provenance,
            requireProvenance: requireProvenance
        )
    }

    public static func issues(
        for designDigest: String,
        provenance: LogicDesignProvenance?,
        requireProvenance: Bool = false
    ) -> [Issue] {
        var issues: [Issue] = []
        if designDigest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.designDigestMissing)
        }
        guard let provenance else {
            if requireProvenance {
                issues.append(.missing)
            }
            return issues
        }
        guard provenance.isValid else {
            issues.append(.invalid)
            return issues
        }
        if let inputDesignDigest = provenance.inputDesignDigest,
           inputDesignDigest != designDigest {
            issues.append(.inputDesignDigestMismatch(expected: designDigest, actual: inputDesignDigest))
        }
        return issues
    }
}
