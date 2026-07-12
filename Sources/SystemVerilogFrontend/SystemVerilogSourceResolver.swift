import Foundation
import LogicIR
import XcircuitePackage

public struct SystemVerilogSourceResolver: SystemVerilogSourceResolving {
    private let sourceProvider: SystemVerilogSourceProviding
    private let lexer: SystemVerilogLexing

    public init(
        sourceProvider: SystemVerilogSourceProviding,
        lexer: SystemVerilogLexing = SystemVerilogLexer()
    ) {
        self.sourceProvider = sourceProvider
        self.lexer = lexer
    }

    public func resolve(_ sources: [SystemVerilogSourceUnit]) throws -> [SystemVerilogSourceUnit] {
        var knownSources: [String: SystemVerilogSourceUnit] = [:]
        for source in sources {
            knownSources[normalizedPath(source.path)] = source
        }

        var resolved: [SystemVerilogSourceUnit] = []
        var visited: Set<String> = []
        var active: [String] = []
        for source in sources {
            try visit(
                source,
                knownSources: knownSources,
                resolved: &resolved,
                visited: &visited,
                active: &active
            )
        }
        return resolved
    }

    private func visit(
        _ source: SystemVerilogSourceUnit,
        knownSources: [String: SystemVerilogSourceUnit],
        resolved: inout [SystemVerilogSourceUnit],
        visited: inout Set<String>,
        active: inout [String]
    ) throws {
        let path = normalizedPath(source.path)
        guard !visited.contains(path) else { return }
        if active.contains(path) {
            throw SystemVerilogSourceResolutionError.cyclicInclude(
                path: path,
                chain: active + [path],
                location: endLocation(for: source)
            )
        }

        active.append(path)
        let lexResult = lexer.lex(source)
        let tokens = lexResult.tokens
        var index = 0
        while index + 2 < tokens.count {
            if tokens[index].lexeme == "`", tokens[index + 1].lexeme == "include" {
                let directiveSpan = LogicSourceSpan(
                    start: tokens[index].span.start,
                    end: tokens[index + 1].span.end
                )
                guard tokens[index + 2].kind == .string, !tokens[index + 2].lexeme.isEmpty else {
                    throw SystemVerilogSourceResolutionError.malformedInclude(
                        sourcePath: source.path,
                        location: directiveSpan
                    )
                }
                let includePath = normalizedPath(
                    resolveRelativePath(tokens[index + 2].lexeme, from: path)
                )
                guard !active.contains(includePath) else {
                    throw SystemVerilogSourceResolutionError.cyclicInclude(
                        path: includePath,
                        chain: active + [includePath],
                        location: tokens[index + 2].span
                    )
                }
                let included: SystemVerilogSourceUnit
                if let knownSource = knownSources[includePath] {
                    included = knownSource
                } else {
                    do {
                        included = try sourceProvider.load(XcircuiteFileReference(
                            path: includePath,
                            kind: .rtl,
                            format: .systemVerilog
                        ))
                    } catch {
                        throw SystemVerilogSourceResolutionError.missingInclude(
                            path: includePath,
                            includingPath: source.path,
                            location: tokens[index + 2].span
                        )
                    }
                }
                try visit(
                    included,
                    knownSources: knownSources,
                    resolved: &resolved,
                    visited: &visited,
                    active: &active
                )
                index += 3
                continue
            }
            index += 1
        }
        _ = active.popLast()
        visited.insert(path)
        resolved.append(source)
    }

    private func resolveRelativePath(_ includePath: String, from sourcePath: String) -> String {
        let isAbsolute = includePath.hasPrefix("/")
        var components = isAbsolute ? [] : sourcePath.split(separator: "/").dropLast().map(String.init)
        for component in includePath.split(separator: "/").map(String.init) {
            switch component {
            case "", ".":
                continue
            case "..":
                if !components.isEmpty { components.removeLast() }
            default:
                components.append(component)
            }
        }
        let prefix = isAbsolute ? "/" : ""
        return prefix + components.joined(separator: "/")
    }

    private func normalizedPath(_ path: String) -> String {
        let isAbsolute = path.hasPrefix("/")
        var components: [String] = []
        for component in path.split(separator: "/").map(String.init) {
            switch component {
            case "", ".":
                continue
            case "..":
                if !components.isEmpty { components.removeLast() }
            default:
                components.append(component)
            }
        }
        let prefix = isAbsolute ? "/" : ""
        return prefix + components.joined(separator: "/")
    }

    private func endLocation(for source: SystemVerilogSourceUnit) -> LogicSourceSpan {
        let line = source.source.split(separator: "\n", omittingEmptySubsequences: false).count
        let column = source.source.split(separator: "\n", omittingEmptySubsequences: false).last?.count ?? 0
        let offset = source.source.utf8.count
        let location = LogicSourceLocation(path: source.path, line: max(1, line), column: max(1, column), offset: offset)
        return LogicSourceSpan(start: location, end: location)
    }
}
