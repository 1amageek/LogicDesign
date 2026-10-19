#if os(WASI)
import WASILibc
#endif
import LogicKernelProbeSupport

@main struct ProbeEntry {
    static func main() {
        guard #available(macOS 26.0, *) else {
            preconditionFailure("Span probes require macOS 26 or newer")
        }
        do {
            try exerciseKernelContract()
            reportProbe("LOGIC_KERNEL_CONTRACT_OK")
            try exerciseLogicValueContract()
            reportProbe("LOGIC_IR_VALUE_CONTRACT_OK")
            try exerciseBitGraphContract()
            reportProbe("LOGIC_BIT_GRAPH_CONTRACT_OK")
            try exerciseWordGraphContract()
            reportProbe("LOGIC_WORD_GRAPH_CONTRACT_OK")
            try exerciseSourceLexicalContract()
            reportProbe("LOGIC_SOURCE_LEXICAL_CONTRACT_OK")
            try exerciseIntegerLiteralContract()
            reportProbe("LOGIC_INTEGER_LITERAL_CONTRACT_OK")
            try exerciseResolvedRTLContract()
            reportProbe("LOGIC_RESOLVED_RTL_CONTRACT_OK")
            try exercisePortableSyntaxContract()
            reportProbe("LOGIC_PORTABLE_SYNTAX_CONTRACT_OK")
            try exerciseBinaryValueContract()
            reportProbe("LOGIC_BINARY_VALUE_CONTRACT_OK")
            try exerciseFourStateValueContract()
            reportProbe("LOGIC_FOUR_STATE_VALUE_CONTRACT_OK")
            try exerciseCellFunctionContract()
            reportProbe("LOGIC_CELL_FUNCTION_CONTRACT_OK")
            try exerciseTechnologyLibraryContract()
            reportProbe("LOGIC_TECHNOLOGY_LIBRARY_CONTRACT_OK")
            try exerciseMappedGraphContract()
            try exerciseMappedClockLineageContract()
            print("LOGIC_CLOCK_LINEAGE_CONTRACT_OK")
            reportProbe("LOGIC_MAPPED_GRAPH_CONTRACT_OK")
            try exerciseMappedRealizationContract()
            reportProbe("LOGIC_MAPPED_REALIZATION_CONTRACT_OK")
            try exerciseParameterBindingContract()
            reportProbe("LOGIC_PARAMETER_BINDING_CONTRACT_OK")
            try exerciseConstantEvaluationContract()
            reportProbe("LOGIC_CONSTANT_EVALUATION_CONTRACT_OK")
            try exerciseParameterOverrideContract()
            reportProbe("LOGIC_PARAMETER_OVERRIDE_CONTRACT_OK")
            try exerciseStaticScopeContract()
            reportProbe("LOGIC_STATIC_SCOPE_CONTRACT_OK")
            try exerciseStaticControlContract()
            reportProbe("LOGIC_STATIC_CONTROL_CONTRACT_OK")
            try exerciseExpressionResolutionContract()
            reportProbe("LOGIC_EXPRESSION_RESOLUTION_CONTRACT_OK")
            try exerciseSourceTextContract()
            reportProbe("LOGIC_SOURCE_TEXT_CONTRACT_OK")
            try exerciseSourcePreprocessingContract()
            reportProbe("LOGIC_SOURCE_PREPROCESSING_CONTRACT_OK")
            try exercisePublicSourceElaborationContract()
            reportProbe("LOGIC_PUBLIC_ELABORATION_CONTRACT_OK")
            try exerciseProgramElaborationContract()
            reportProbe("LOGIC_PROGRAM_ELABORATION_CONTRACT_OK")
        } catch { preconditionFailure("Kernel contract probe failed") }
    }
}

private nonisolated func reportProbe(_ message: String) {
    print(message)
    #if os(WASI)
    fflush(nil)
    #endif
}
