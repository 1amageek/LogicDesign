// swift-tools-version: 6.3
import PackageDescription
import Foundation

let workspaceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let circuiteFoundationDependency: Package.Dependency = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("CircuiteFoundation/Package.swift").path
)
    ? .package(path: "../CircuiteFoundation")
    : .package(
        url: "https://github.com/1amageek/CircuiteFoundation.git",
        revision: "2ec6ee13a89ac6885be3c26b41a9ee0ef89948ac"
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
