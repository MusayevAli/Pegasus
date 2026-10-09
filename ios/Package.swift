// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TripFitCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "TripFitCore", targets: ["TripFitCore"])],
    targets: [
        .target(name: "TripFitCore"),
        .testTarget(name: "TripFitCoreTests", dependencies: ["TripFitCore"])
    ]
)
