// swift-tools-version: 5.9
import PackageDescription

// Shared fish engine for Bigger Fish (arcade) and the education app.
let package = Package(
    name: "FishKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "FishKit", targets: ["FishKit"]),
    ],
    targets: [
        .target(name: "FishKit"),
        .testTarget(name: "FishKitTests", dependencies: ["FishKit"]),
    ]
)
