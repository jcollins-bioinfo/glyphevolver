// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlyphEvolver",
    platforms: [.macOS(.v15), .iOS("27.0")],
    products: [.library(name: "GlyphCore", targets: ["GlyphCore"]),
               .executable(name: "triplet-simulation", targets: ["TripletSimulation"])],
    targets: [
        .target(name: "GlyphCore", resources: [.process("Resources")]),
        .executableTarget(name: "TripletSimulation", dependencies: ["GlyphCore"]),
        .testTarget(name: "GlyphCoreTests", dependencies: ["GlyphCore"])
    ]
)
