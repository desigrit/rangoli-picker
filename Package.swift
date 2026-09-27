// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Rangoli",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Rangoli", targets: ["Rang"]),
        .executable(name: "RangoliLoginLauncher", targets: ["RangLoginLauncher"]),
        .executable(name: "RangCoreChecks", targets: ["RangCoreChecks"])
    ],
    targets: [
        .target(name: "RangCore"),
        .executableTarget(name: "Rang", dependencies: ["RangCore"]),
        .executableTarget(name: "RangLoginLauncher"),
        .executableTarget(name: "RangCoreChecks", dependencies: ["RangCore"])
    ]
)
