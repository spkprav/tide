// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tide",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tide", targets: ["Tide"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Tide",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/Tide"
        ),
    ]
)
