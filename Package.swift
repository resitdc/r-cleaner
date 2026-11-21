// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RCleaner",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "RCleaner", targets: ["RCleaner"])
    ],
    targets: [
        .executableTarget(
            name: "RCleaner",
            path: "Sources/RCleaner",
            resources: [
                .copy("Resources/VoicePack")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("Vision"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .testTarget(
            name: "RCleanerTests",
            dependencies: ["RCleaner"],
            path: "Tests/RCleanerTests"
        )
    ]
)
