import Foundation

public protocol SystemVerilogParsing: Sendable {
    func parse(_ sources: [SystemVerilogSourceUnit], topDesignName: String) -> SystemVerilogParseResult

    /// Parses sources after an include graph has been resolved by the caller.
    /// Implementations that do not support resolved includes retain the default
    /// behavior and use the ordinary parser contract.
    func parseResolvedIncludes(
        _ sources: [SystemVerilogSourceUnit],
        topDesignName: String
    ) -> SystemVerilogParseResult
}

public extension SystemVerilogParsing {
    func parseResolvedIncludes(
        _ sources: [SystemVerilogSourceUnit],
        topDesignName: String
    ) -> SystemVerilogParseResult {
        parse(sources, topDesignName: topDesignName)
    }
}
