// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ToolIsle",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ToolIsle", targets: ["ToolIsleApp"]), .library(name: "ToolIsleCore", targets: ["ToolIsleCore"])],
    dependencies: [.package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1")],
    targets: [
        .target(name: "ToolIsleCore", path: "ToolIsle/Core"),
        .executableTarget(name: "ToolIsleApp", dependencies: ["ToolIsleCore", .product(name: "MarkdownUI", package: "swift-markdown-ui")], path: "ToolIsle/App", resources: [.copy("Resources")]),
        .testTarget(name: "ToolIsleCoreTests", dependencies: ["ToolIsleCore"], path: "ToolIsle/Tests")
    ],
    swiftLanguageModes: [.v5]
)
