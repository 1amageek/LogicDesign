import Foundation
import CircuiteFoundationFoundation
import LogicIR

extension LogicDataflowFIFOConfiguration: Codable {
    private enum CodingKeys: String, CodingKey { case `depth`, `bypass`, `implementationName`, `inputFlopKind`, `outputFlopKind` }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let depth = try container.decodeIfPresent(Int.self, forKey: .`depth`)
        let bypass = try container.decodeIfPresent(Bool.self, forKey: .`bypass`)
        let implementationName = try container.decodeIfPresent(String.self, forKey: .`implementationName`)
        let inputFlopKind = try container.decodeIfPresent(LogicDataflowFlopKind.self, forKey: .`inputFlopKind`)
        let outputFlopKind = try container.decodeIfPresent(LogicDataflowFlopKind.self, forKey: .`outputFlopKind`)
        self.init(depth: depth, bypass: bypass, implementationName: implementationName, inputFlopKind: inputFlopKind, outputFlopKind: outputFlopKind)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(depth, forKey: .`depth`)
        try container.encodeIfPresent(bypass, forKey: .`bypass`)
        try container.encodeIfPresent(implementationName, forKey: .`implementationName`)
        try container.encodeIfPresent(inputFlopKind, forKey: .`inputFlopKind`)
        try container.encodeIfPresent(outputFlopKind, forKey: .`outputFlopKind`)
    }
}
