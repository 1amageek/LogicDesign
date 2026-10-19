public enum LogicResource: UInt8, Sendable, Hashable, CaseIterable {
    case bitWidth
    case expansion
    case nodes
    case edges
    case states
    case managedStorageBytes
    case storageReservations
    case allocationBytes
    case workUnits
    case outputBytes
    case cnfVariables
    case cnfClauses
    case proofBytes
    case searchSteps
}
