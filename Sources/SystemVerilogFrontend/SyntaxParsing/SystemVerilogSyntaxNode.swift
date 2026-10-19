package struct SystemVerilogSyntaxNode: Sendable {
    package enum Unary: Sendable, Equatable {
        case plus, minus, invert, logicalNot, reduceAnd, reduceOr, reduceXor, reduceNand, reduceNor, reduceXnor
    }
    package enum Binary: Sendable, Equatable {
        case multiply, add, subtract, shiftLeft, shiftRight, arithmeticLeft, arithmeticRight
        case less, lessEqual, greater, greaterEqual, equal, notEqual, caseEqual, caseNotEqual
        case and, xor, xnor, or, logicalAnd, logicalOr
    }
    package enum Selection: Sendable, Equatable { case bit, range, indexedUp, indexedDown }
    package enum BaseType: Sendable, Equatable { case logic, bit, int, integer }
    package enum Storage: Sendable, Equatable { case unspecified, net, variable }
    package enum Declaration: Sendable, Equatable { case variable, net, parameter, localParameter, genvar }
    package enum Direction: Sendable, Equatable { case input, output, inoutPort }
    package enum Process: Sendable, Equatable { case continuous, always, combinational, flipFlop, latch, initial }
    package enum Edge: Sendable, Equatable { case level, rising, falling }
    package enum Assignment: Sendable, Equatable {
        case blocking, nonBlocking, add, subtract, increment, decrement
    }
    package enum Kind: Sendable {
        case identifier(Int), literal
        case unary(Unary, Int), binary(Binary, Int, Int), conditional(Int, Int, Int)
        case concatenate(Range<Int>), repeated(Int, Int)
        case select(Selection, value: Int, first: Int, second: Int?)
        case signedCast(Bool, Int)
        case packedRange(Int, Int)
        case type(BaseType, signed: Bool?, dimensions: Range<Int>, storage: Storage, explicitBase: Bool)
        case declaration(Declaration, name: Int, type: Int?, initial: Int?)
        case port(Direction?, name: Int, type: Int?, initial: Int?)
        case module(name: Int, parameters: Range<Int>, ports: Range<Int>, items: Range<Int>, hasParameterPortList: Bool)
        case binding(name: Int?, value: Int?)
        case instance(module: Int, name: Int, parameters: Range<Int>, ports: Range<Int>)
        case group(Range<Int>)
        case process(Process, sensitivity: Int?, body: Int)
        case sensitivity(all: Bool, terms: Range<Int>)
        case event(Edge, Int)
        case assignment(Assignment, target: Int, value: Int?)
        case block(label: Int?, statements: Range<Int>)
        case ifStatement(condition: Int, then: Int, elseBody: Int?)
        case caseStatement(selector: Int, arms: Range<Int>)
        case caseArm(matches: Range<Int>, body: Int)
        case forStatement(initial: Int, condition: Int, step: Int, body: Int)
        case generateRegion(Range<Int>)
        case generateBlock(label: Int?, items: Range<Int>)
        case generateIf(condition: Int, then: Int, elseBody: Int?)
        case generateCase(selector: Int, arms: Range<Int>)
        case generateFor(initial: Int, condition: Int, step: Int, body: Int)
        case empty
    }
    package let kind: Kind
    package let byteRange: Range<Int>
}

extension SystemVerilogSyntaxNode.Kind {
    internal var referenceCount: Int {
        switch self {
        case .unary, .signedCast, .event: return 1
        case .binary, .repeated, .packedRange: return 2
        case .conditional: return 3
        case .select(_, _, _, let second): return second == nil ? 2 : 3
        case .declaration(_, _, let type, let initial), .port(_, _, let type, let initial):
            return (type == nil ? 0 : 1) + (initial == nil ? 0 : 1)
        case .binding(_, let value): return value == nil ? 0 : 1
        case .process(_, let sensitivity, _): return sensitivity == nil ? 1 : 2
        case .assignment(_, _, let value): return value == nil ? 1 : 2
        case .ifStatement(_, _, let elseBody), .generateIf(_, _, let elseBody): return elseBody == nil ? 2 : 3
        case .caseStatement, .caseArm, .generateCase: return 1
        case .forStatement, .generateFor: return 4
        case .identifier, .literal, .concatenate, .type, .module, .instance, .group,
             .sensitivity, .block, .generateRegion, .generateBlock, .empty: return 0
        }
    }
}
