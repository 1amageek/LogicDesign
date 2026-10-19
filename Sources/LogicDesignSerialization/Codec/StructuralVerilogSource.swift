/// Immutable facts from one completely admitted flat structural source.
public struct StructuralVerilogSource: Sendable {
    public struct Port: Sendable {
        public enum Direction: Sendable { case input, output }
        public let name: String
        public let direction: Direction
        /// A deterministic declared representative of the electrical alias component.
        public let netName: String
        public let byteRange: Range<Int>
    }
    public struct Net: Sendable {
        public let name: String
        public let canonicalName: String
        public let constant: Bool?
        public let constantByteRange: Range<Int>?
        public let byteRange: Range<Int>
    }
    public struct PinConnection: Sendable {
        public let pinName: String
        public let netName: String
        public let canonicalNetName: String
        public let byteRange: Range<Int>
    }
    public struct Instance: Sendable {
        public let name: String
        public let cellName: String
        public let connections: [PinConnection]
        public let byteRange: Range<Int>
    }
    public struct Alias: Sendable {
        public let target: String
        public let source: String
        public let byteRange: Range<Int>
    }
    public let top: String
    public let byteRange: Range<Int>
    public let ports: [Port]
    public let nets: [Net]
    public let instances: [Instance]
    public let aliases: [Alias]
}
