// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "alarmooh",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Nur noetig, solange kein vollstaendiges Xcode installiert ist:
        // die Command Line Tools liefern weder XCTest noch Testing mit.
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.10.0"),
    ],
    targets: [
        .target(name: "AlarmoohCore"),
        .executableTarget(name: "alarmooh", dependencies: ["AlarmoohCore"]),
        .testTarget(
            name: "AlarmoohCoreTests",
            dependencies: ["AlarmoohCore", .product(name: "Testing", package: "swift-testing")]
        ),
    ]
)
