// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "PlateLab", platforms: [.macOS(.v14)],
    products: [.executable(name: "PlateLab", targets: ["PlateLab"])],
    targets: [
        .executableTarget(name: "PlateLab"),
        .testTarget(name: "PlateLabTests", dependencies: ["PlateLab"])
    ]
)
