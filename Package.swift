// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "dida",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "dida",
            path: "Sources/dida"
        )
    ]
)
