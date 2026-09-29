// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AirTrackCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AirTrackCore", targets: ["AirTrackCore"]),
    ],
    targets: [
        .target(name: "AirTrackCore"),
        .testTarget(name: "AirTrackCoreTests", dependencies: ["AirTrackCore"]),
    ]
)
