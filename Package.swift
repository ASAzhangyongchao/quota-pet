// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotaPet",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "QuotaPet", targets: ["QuotaPet"]),
    ],
    targets: [
        .executableTarget(
            name: "QuotaPet",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .testTarget(name: "QuotaPetTests", dependencies: ["QuotaPet"]),
    ],
    swiftLanguageModes: [.v5]
)
