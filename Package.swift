// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RedGIFsApp",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "RedGIFsApp", targets: ["RedGIFsApp"]),
    ],
    targets: [
        .target(
            name: "RedGIFsApp",
            path: "Sources/RedGIFsApp"
        ),
    ]
)
