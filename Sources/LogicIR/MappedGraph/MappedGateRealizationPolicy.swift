public enum MappedGateRealizationPolicy: Sendable {
    /// Structural Verilog permits logical constant assignments, but cannot invent cell startup.
    case standardNetlist
    /// Every driver must be a primary input or an actual cell output, including constants.
    case physicalCells
}
