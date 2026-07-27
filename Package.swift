// swift-tools-version: 6.3
import PackageDescription
import Foundation

let workspaceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let isLSIWorkspace = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("docs/workspace-packages.json").path
)
let circuiteFoundationDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("CircuiteFoundation/Package.swift").path
)
    ? .package(path: "../CircuiteFoundation")
    : .package(
        url: "https://github.com/1amageek/CircuiteFoundation.git",
        revision: "1dd75ecf2b8758c54c4e008ff5fd59e263cce0e6"
    )

let package = Package(
    name: "LogicDesign",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LogicIR", targets: ["LogicIR"]),
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
            name: "LogicIR",
            dependencies: [.product(name: "CircuiteFoundation", package: "CircuiteFoundation")]
        ),
        .target(
            name: "SystemVerilogFrontend",
            dependencies: [.product(name: "CircuiteFoundation", package: "CircuiteFoundation"), "LogicIR"]
        ),
        .target(
            name: "PowerIntent",
            dependencies: [.product(name: "CircuiteFoundation", package: "CircuiteFoundation"), "LogicIR"]
        ),
        .target(
            name: "LogicDesign",
            dependencies: ["LogicIR", "SystemVerilogFrontend", "PowerIntent"]
        ),
        .executableTarget(
            name: "LogicDesignCLI",
            dependencies: ["LogicIR", "SystemVerilogFrontend", "PowerIntent", "LogicDesign", .product(name: "CircuiteFoundation", package: "CircuiteFoundation")]
        ),
        .testTarget(
            name: "LogicDesignTests",
            dependencies: ["LogicIR", "SystemVerilogFrontend", "PowerIntent", "LogicDesign", "LogicDesignCLI", .product(name: "CircuiteFoundation", package: "CircuiteFoundation")],
            resources: [.copy("../../Fixtures")]
        ),
    ]
)
