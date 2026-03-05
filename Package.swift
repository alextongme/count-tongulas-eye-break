// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EyeBreak",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/airbnb/lottie-ios.git", from: "4.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "eye_break_ui",
            dependencies: [
                .product(name: "Lottie", package: "lottie-ios"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "scripts/Sources",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("IOKit"),
            ]
        ),
    ]
)
