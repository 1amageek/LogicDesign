import Foundation
import LogicDesignSerialization
import LogicKernelCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct StructuralVerilogSourceTests {
    private struct Running: LogicRunControlling { func checkpoint() throws(LogicKernelError) {} }
    private func context(_ overrides: [LogicResource: UInt64] = [:],
                         control: any LogicRunControlling = Running()) throws -> LogicKernelContext {
        var maximums = Dictionary(uniqueKeysWithValues: LogicResource.allCases.map { ($0, UInt64(10_000_000)) })
        for (resource, amount) in overrides { maximums[resource] = amount }
        return .init(limits: try .init(maximums: maximums), control: control)
    }
    @available(macOS 26.0, *)
    private func decode(_ text: String, top: String = "top") throws -> StructuralVerilogSource {
        var run = try context()
        return try MappedGateVerilogCodec().decodeSource(Data(text.utf8), top: top, context: &run)
    }
    private func slice(_ text: String, _ range: Range<Int>) -> String {
        String(decoding: Array(text.utf8)[range], as: UTF8.self)
    }
    @available(macOS 26.0, *)
    @Test func actualSourceConnectionsAndAliasesNeedNoMappedSidecar() throws {
        let text = #"""
        module \top-name (\a ,\y );
        input \a ;
        output \y ;
        wire \route-1/internal ;
        assign \y =\route-1/internal ;
        \INV \cts_net-4_cell-0/CLK (.\A (\a ),.\Y (\route-1/internal ));
        endmodule
        """# + "\n"
        var run = try context()
        let codec: any StructuralVerilogSourceDecoding = MappedGateVerilogCodec()
        let result = try codec.decodeSource(Data(text.utf8), top: "top-name", context: &run)
        #expect(result.top == "top-name" && result.ports.count == 2 && result.instances.count == 1)
        #expect(result.instances[0].name == "cts_net-4_cell-0/CLK")
        #expect(result.instances[0].connections[1].netName == "route-1/internal")
        #expect(result.ports[1].netName == result.instances[0].connections[1].canonicalNetName)
        #expect(result.aliases[0].target == "y" && result.aliases[0].source == "route-1/internal")
    }

    @available(macOS 26.0, *)
    @Test func generatedNamesConstantsAliasesUnusedNetsAndExactRanges() throws {
        let text = #"""
        module \top (p0_0,p1_0);
        input p0_0;
        output p1_0;
        wire n0;
        wire n1;
        wire n2;
        wire n3;
        assign n0=p0_0;
        assign n1=1'b1;
        assign n2=n1;
        assign p1_0=n2;
        \gate:inv i0(.\A (n0),.\Y (n3));
        endmodule
        """# + "\n"
        let result = try decode(text)
        #expect(result.nets.count == 6 && result.aliases.count == 3)
        let output = try #require(result.nets.first { $0.name == "p1_0" })
        let constant = try #require(result.nets.first { $0.name == "n1" })
        #expect(output.canonicalName == constant.canonicalName && output.constant == true)
        #expect(slice(text, try #require(output.constantByteRange)) == "assign n1=1'b1;")
        #expect(slice(text, result.ports[0].byteRange) == "p0_0")
        #expect(slice(text, result.instances[0].byteRange) == #"\gate:inv i0(.\A (n0),.\Y (n3));"#)
        let dangling = try decode(#"module \top (); wire \dangling ; endmodule"#)
        #expect(dangling.nets.count == 1 && dangling.instances.isEmpty && dangling.nets[0].constant == nil)
        let redeclared = try decode(#"module \top (\a ); input \a ; wire \a ; endmodule"#)
        #expect(redeclared.nets.count == 1)
    }

    @available(macOS 26.0, *)
    @Test func changedTextAndEscapedKeywordsAreActualSourceFacts() throws {
        let text = #"module \module (\input ,\endmodule ); input \input ; output \endmodule ; wire \route-1/X ; assign \endmodule =\route-1/X ; \assign \wire (.\input (\input ),.\output (\route-1/X )); endmodule"#
        let original = try decode(text, top: "module")
        let changed = try decode(text.replacingOccurrences(of: "=\\route-1/X ", with: "=\\input "), top: "module")
        #expect(original.ports[1].netName != changed.ports[1].netName)
        #expect(changed.ports[1].netName == changed.ports[0].netName)
        #expect(original.instances[0].cellName == "assign" && original.instances[0].name == "wire")
    }

    @available(macOS 26.0, *)
    @Test func completeSyntaxAndDeclaredUniqueScalarIdentityAreRequired() throws {
        let invalid = [
            #"module \top (\a ,\a ); input \a ; input \a ; endmodule"#,
            #"module \top (\a ); output \other ; endmodule"#,
            #"module \top (\a ); input \a ; wire \a ; wire \a ; endmodule"#,
            #"module \top (\a ); input \a ; assign \a =1'b0; endmodule"#,
            #"module \top (); wire \n ; assign \n =1'b0; assign \n =1'b1; endmodule"#,
            #"module \top (); \BUF \u (.\A (\missing )); endmodule"#,
            #"module \top (); wire \a ; \BUF \u (.\A (\a ),.\A (\a )); endmodule"#,
            #"module \top (); wire \a ; \BUF \u (.\A (\a )); \BUF \u (.\A (\a )); endmodule"#,
            #"module \top (); wire \u ; \BUF \u (.\A (\u )); endmodule"#,
            #"module \top (); wire \a ; assign \a =\a ; endmodule"#,
            #"module \top (); wire \a ; wire \b ; assign \a =\b ; assign \b =\a ; endmodule"#,
            #"module \top (); wire \a ; wire \b ; assign \a =\b &\b ; endmodule"#,
            #"module \top (); wire [1:0] a; endmodule"#,
            #"module \top (); wire \a ; \BUF \u (\a ); endmodule"#,
            #"module \top (); \BUF \u (); endmodule"#,
            #"module \top (); wire \a ; \BUF \u (.\A ()); endmodule"#,
            #"module \top (); wire \a ; assign \a =1'bx; endmodule"#,
            #"module \top (); endmodule module \second (); endmodule"#,
            #"module \top (); endmodule trailing"#,
            "module \\top (); // comment\nendmodule",
            #"module \top (); wire arbitrary; endmodule"#,
            #"module \top (); wire n01; endmodule"#,
            #"module \top (); wire \é ; endmodule"#
        ]
        for text in invalid {
            var run = try context()
            do {
                _ = try MappedGateVerilogCodec().decodeSource(Data(text.utf8), top: "top", context: &run)
                Issue.record("Unsupported or malformed source was accepted: \(text)")
            } catch let error {
                switch error {
                case .malformed(let range, _), .unsupported(let range, _):
                    #expect(range.lowerBound >= 0 && range.upperBound <= text.utf8.count)
                case .kernel: Issue.record("Syntax counterexample reached a budget failure")
                }
            }
            #expect(run.usage[.managedStorageBytes] == 0)
        }
        #expect(throws: StructuralVerilogSourceError.self) { try decode(#"module \other (); endmodule"#) }
        #expect(throws: StructuralVerilogSourceError.self) { try decode(#"module \top (); wire \a ; assign \a ="#) }
    }

    @available(macOS 26.0, *)
    @Test func inputByteFailuresKeepOriginalRanges() throws {
        let unterminated = #"module \top (); wire \bad"#
        var run = try context()
        do {
            _ = try MappedGateVerilogCodec().decodeSource(Data(unterminated.utf8), top: "top", context: &run)
            Issue.record("Unterminated identifier was accepted")
        } catch let error {
            guard case .malformed(let range, _) = error else { Issue.record("Wrong lexical failure"); return }
            #expect(slice(unterminated, range) == #"\bad"#)
        }
        #expect(run.usage[.managedStorageBytes] == 0)
        let nul = Data(#"module \top (); endmodule"#.utf8) + Data([0])
        do {
            _ = try MappedGateVerilogCodec().decodeSource(nul, top: "top", context: &run)
            Issue.record("NUL was silently discarded as whitespace")
        } catch let error {
            guard case .unsupported(let range, _) = error else { Issue.record("Wrong control-byte failure"); return }
            #expect(range == (nul.count - 1)..<nul.count)
        }
        #expect(run.usage[.managedStorageBytes] == 0)
        do {
            _ = try MappedGateVerilogCodec().decodeSource(Data([0xff]), top: "top", context: &run)
            Issue.record("Invalid UTF-8 was accepted")
        } catch let error {
            guard case .malformed(let range, _) = error else { Issue.record("Wrong UTF-8 failure"); return }
            #expect(range == 0..<1)
        }
        #expect(run.usage[.managedStorageBytes] == 0)
    }

    @available(macOS 26.0, *)
    @Test func finiteCumulativeResourcesAndCancellationOwnAllFailureCleanup() throws {
        let text = #"module \top (\a ,\y ); input \a ; output \y ; assign \y =\a ; endmodule"#
        let data = Data(text.utf8), codec = MappedGateVerilogCodec()
        var baseline = try context()
        let result = try codec.decodeSource(data, top: "top", context: &baseline)
        #expect(baseline.usage[.expansion] == UInt64(data.count))
        #expect(baseline.usage[.storageReservations] == 3 && baseline.usage[.nodes] == 6)
        #expect(baseline.usage[.managedStorageBytes] > 0)
        var stringBytes = UInt64(result.top.utf8.count)
        for port in result.ports { stringBytes += UInt64(port.name.utf8.count + port.netName.utf8.count) }
        for net in result.nets { stringBytes += UInt64(net.name.utf8.count + net.canonicalName.utf8.count) }
        for alias in result.aliases { stringBytes += UInt64(alias.target.utf8.count + alias.source.utf8.count) }
        #expect(baseline.usage[.outputBytes] == stringBytes)
        for resource in [LogicResource.expansion, .workUnits, .nodes, .outputBytes, .managedStorageBytes, .allocationBytes, .storageReservations] {
            var run = try context([resource: 1])
            do {
                _ = try codec.decodeSource(data, top: "top", context: &run)
                Issue.record("Resource limit was bypassed: \(resource)")
            } catch let error {
                guard case .kernel(.resourceLimit(let actual, _, _)) = error else {
                    Issue.record("Wrong quota failure: \(error)"); continue
                }
                #expect(actual == resource)
            }
            #expect(run.usage[.managedStorageBytes] == 0)
        }
        var late = try context([.workUnits: baseline.usage[.workUnits] - 1])
        #expect(throws: StructuralVerilogSourceError.self) { try codec.decodeSource(data, top: "top", context: &late) }
        #expect(late.usage[.managedStorageBytes] == 0 && late.usage[.storageReservations] == 3)
        let cancellation = LogicCancellationSource(); cancellation.cancel()
        var cancelled = try context(control: cancellation)
        do {
            _ = try codec.decodeSource(data, top: "top", context: &cancelled)
            Issue.record("Cancelled intake succeeded")
        } catch let error {
            guard case .kernel(.cancelled) = error else { Issue.record("Lost cancellation cause"); return }
        }
        #expect(cancelled.usage[.allocationBytes] == 0)
        var cumulative = try context([.outputBytes: stringBytes * 2 - 1])
        _ = try codec.decodeSource(data, top: "top", context: &cumulative)
        let retained = cumulative.usage[.managedStorageBytes]
        #expect(throws: StructuralVerilogSourceError.self) { try codec.decodeSource(data, top: "top", context: &cumulative) }
        #expect(cumulative.usage[.managedStorageBytes] == retained && cumulative.usage[.outputBytes] == stringBytes)
        let used: Set<LogicResource> = [.expansion, .workUnits, .nodes, .outputBytes, .managedStorageBytes, .allocationBytes, .storageReservations]
        var unusedOne: [LogicResource: UInt64] = [:]
        for resource in LogicResource.allCases where !used.contains(resource) { unusedOne[resource] = 1 }
        var minimal = try context(unusedOne)
        _ = try codec.decodeSource(data, top: "top", context: &minimal)
        for resource in LogicResource.allCases where !used.contains(resource) { #expect(minimal.usage[resource] == 0) }
    }
}
