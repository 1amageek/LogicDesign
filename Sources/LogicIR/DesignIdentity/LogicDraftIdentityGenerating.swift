public protocol LogicDraftIdentityGenerating: Sendable {
    func make(kind: String, path: String, name: String) -> String
}
