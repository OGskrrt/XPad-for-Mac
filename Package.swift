// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "XPad",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "XPad",
            path: "Sources/XPad",
            linkerSettings: [
                .linkedFramework("IOUSBHost"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
