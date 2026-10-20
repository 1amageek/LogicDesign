// swift-tools-version: 6.4
import PackageDescription

let circuiteFoundationDependency: Package.Dependency = .package(
    url: "https://github.com/1amageek/CircuiteFoundation.git",
    exact: "26.1021.0"
)

let package = Package(
    name: "LogicDesign",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LogicKernelCore", targets: ["LogicKernelCore"]),
        .library(name: "LogicIR", targets: ["LogicIR"]),
        .library(name: "LogicDesignSerialization", targets: ["LogicDesignSerialization"]),
        .library(name: "SystemVerilogFrontend", targets: ["SystemVerilogFrontend"]),
        .library(name: "PowerIntent", targets: ["PowerIntent"]),
        .library(name: "LogicDesign", targets: ["LogicDesign"]),
        .executable(name: "logic-design", targets: ["LogicDesignCLI"]),
    ],
    dependencies: [
        circuiteFoundationDependency,
    ],
    targets: [
        .target(
            name: "LogicKernelCore",
            dependencies: [.product(name: "CircuiteFoundation", package: "CircuiteFoundation")],
            exclude: ["DESIGN.md", "ExecutionControl/DESIGN.md"]
        ),
        .testTarget(
            name: "LogicKernelCoreTests",
            dependencies: ["LogicKernelCore", .product(name: "CircuiteFoundation", package: "CircuiteFoundation")]
        ),
        .target(name: "LogicKernelProbeSupport", dependencies: ["LogicKernelCore", "LogicIR", "SystemVerilogFrontend", .product(name: "CircuiteFoundation", package: "CircuiteFoundation")]),
        .executableTarget(
            name: "LogicKernelPortabilityProbe",
            dependencies: ["LogicKernelProbeSupport"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=4194304"], .when(platforms: [.wasi]))]
        ),
        .executableTarget(
            name: "LogicKernelEmbeddedPortabilityProbe",
            dependencies: ["LogicKernelProbeSupport"],
            linkerSettings: [
                .linkedLibrary("swiftUnicodeDataTables", .when(platforms: [.wasi])),
                .unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=4194304"], .when(platforms: [.wasi]))
            ]
        ),
        .target(
            name: "LogicIR",
            dependencies: ["LogicKernelCore", .product(name: "CircuiteFoundation", package: "CircuiteFoundation")],
            exclude: ["DESIGN.md", "RTLModel/DESIGN.md", "GateModel/DESIGN.md", "Dataflow/DESIGN.md", "DesignIdentity/DESIGN.md", "Validation/DESIGN.md", "LogicValues/DESIGN.md", "CellFunctions/DESIGN.md", "TechnologyLibrary/DESIGN.md", "MappedGraph/DESIGN.md", "BitGraph/DESIGN.md", "WordGraph/DESIGN.md", "GraphConnectivity/DESIGN.md", "SourceModel/DESIGN.md", "ResolvedRTL/DESIGN.md"]
        ),
        .target(
            name: "LogicDesignSerialization",
            dependencies: [
                "LogicIR",
                "LogicKernelCore",
                .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation")
            ],
            exclude: ["DESIGN.md", "Codec/DESIGN.md", "Conformances/DESIGN.md"]
        ),
        .target(
            name: "SystemVerilogFrontend",
            dependencies: ["LogicIR", "LogicKernelCore", .product(name: "CircuiteFoundation", package: "CircuiteFoundation")],
            exclude: ["DESIGN.md", "SourceText/DESIGN.md", "SourcePreprocessing/DESIGN.md", "SourceElaboration/DESIGN.md", "LexicalAnalysis/DESIGN.md", "IntegerLiterals/DESIGN.md", "SyntaxParsing/DESIGN.md", "ParameterBinding/DESIGN.md", "ConstantEvaluation/DESIGN.md", "InstanceParameters/DESIGN.md", "StaticScopes/DESIGN.md", "StaticControl/DESIGN.md", "ExpressionResolution/DESIGN.md", "ProgramElaboration/DESIGN.md"]
        ),
        .target(
            name: "PowerIntent",
            dependencies: [
                "LogicDesignSerialization",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
                "LogicIR",
            ]
        ),
        .target(
            name: "LogicDesign",
            dependencies: [
                "LogicDesignSerialization",
                "LogicKernelCore",
                "LogicIR",
                "SystemVerilogFrontend",
                "PowerIntent",
                .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
            ],
            exclude: ["DESIGN.md", "SourceAcquisition/DESIGN.md", "LegacySystemVerilog/DESIGN.md", "HostElaboration/DESIGN.md"]
        ),
        .executableTarget(
            name: "LogicDesignCLI",
            dependencies: [
                "LogicDesignSerialization",
                "LogicKernelCore",
                "LogicIR",
                "SystemVerilogFrontend",
                "PowerIntent",
                "LogicDesign",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
            ]
        ),
        .testTarget(
            name: "LogicDesignTests",
            dependencies: [
                "LogicDesignSerialization",
                "LogicKernelProbeSupport",
                "LogicKernelCore",
                "LogicIR",
                "SystemVerilogFrontend",
                "PowerIntent",
                "LogicDesign",
                "LogicDesignCLI",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
                .product(name: "CircuiteFoundationCrypto", package: "CircuiteFoundation"),
            ],
            resources: [.copy("../../Fixtures")]
        ),
    ]
)
