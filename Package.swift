// swift-tools-version: 5.9
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let appSourcesPath = packageRoot.appendingPathComponent("Sources/SchoolTrackerApp").path
let hasAppTarget = FileManager.default.fileExists(atPath: appSourcesPath)

var products: [Product] = [
    .library(
        name: "SchoolTrackerCore",
        targets: ["SchoolTrackerCore"]
    )
]

var targets: [Target] = [
    .target(
        name: "SchoolTrackerCore",
        path: "Sources/SchoolTrackerCore"
    ),
    .testTarget(
        name: "SchoolTrackerCoreTests",
        dependencies: ["SchoolTrackerCore"],
        path: "Tests/SchoolTrackerCoreTests"
    )
]

if hasAppTarget {
    products.append(
        .executable(
            name: "SchoolTrackerApp",
            targets: ["SchoolTrackerApp"]
        )
    )
    targets.append(
        .executableTarget(
            name: "SchoolTrackerApp",
            dependencies: ["SchoolTrackerCore"],
            path: "Sources/SchoolTrackerApp"
        )
    )
}

let package = Package(
    name: "SchoolTracker",
    platforms: [
        .macOS(.v14)
    ],
    products: products,
    targets: targets
)
