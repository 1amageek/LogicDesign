public protocol LogicRunControlling: Sendable {
    func checkpoint() throws(LogicKernelError)
}
