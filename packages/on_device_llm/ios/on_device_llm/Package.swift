// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "on_device_llm",
    platforms: [.iOS("15.0")],
    products: [
        .library(name: "on-device-llm", targets: ["on_device_llm"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "on_device_llm",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
