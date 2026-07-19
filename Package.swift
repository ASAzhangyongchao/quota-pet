// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotaPet",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "QuotaPet", targets: ["QuotaPet"]),
    ],
    targets: [
        .executableTarget(
            name: "QuotaPet",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .testTarget(name: "QuotaPetTests", dependencies: ["QuotaPet"]),
    ],
    swiftLanguageModes: [.v5]
)
