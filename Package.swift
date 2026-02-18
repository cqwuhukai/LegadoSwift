// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LegadoSwift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "LegadoSwiftApp",
            targets: ["LegadoSwiftApp"]
        ),
        .library(
            name: "LegadoSwiftCore",
            targets: ["LegadoSwiftCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.1"),
    ],
    targets: [
        .executableTarget(
            name: "LegadoSwiftApp",
            dependencies: ["LegadoSwiftCore"],
            path: "Sources/LegadoSwiftApp",
            resources: [
                .copy("../../Assets.xcassets")
            ]
        ),
        .target(
            name: "LegadoSwiftCore",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ],
            path: "Sources/LegadoSwiftCore",
            linkerSettings: [
                .linkedFramework("JavaScriptCore")
            ]
        ),
    ]
)
