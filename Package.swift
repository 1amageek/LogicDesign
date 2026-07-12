// swift-tools-version: 6.3
import PackageDescription

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
        .package(url: "https://github.com/1amageek/XcircuitePackage.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "LogicIR",
            dependencies: [.product(name: "XcircuitePackage", package: "XcircuitePackage")]
        ),
        .target(
            name: "SystemVerilogFrontend",
            dependencies: [.product(name: "XcircuitePackage", package: "XcircuitePackage"), "LogicIR"]
        ),
        .target(
            name: "PowerIntent",
            dependencies: [.product(name: "XcircuitePackage", package: "XcircuitePackage"), "LogicIR"]
        ),
        .target(
            name: "LogicDesign",
            dependencies: ["LogicIR", "SystemVerilogFrontend", "PowerIntent"]
        ),
        .executableTarget(
            name: "LogicDesignCLI",
            dependencies: ["LogicIR", "SystemVerilogFrontend", "PowerIntent", "LogicDesign"]
        ),
        .testTarget(
            name: "LogicDesignTests",
            dependencies: ["LogicIR", "SystemVerilogFrontend", "PowerIntent", "LogicDesign", "LogicDesignCLI"]
        ),
    ]
)
