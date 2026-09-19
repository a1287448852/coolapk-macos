// swift-tools-version: 6.2
import Foundation
import PackageDescription

let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "CoolapkMac",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "CoolapkMac", targets: ["CoolapkMac"])
    ],
    targets: [
        // C 层:uniFFI 生成的头文件 + 链接 Rust 静态库
        .target(
            name: "CoolapkCoreFFI",
            path: "Sources/CoolapkCoreFFI",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedLibrary("coolapk_core"),
                // Rust 侧 reqwest/security-framework 需要的系统框架
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("Security"),
                .linkedFramework("CoreFoundation"),
                .unsafeFlags(["-L", "\(packageDir)/Vendor/lib"]),
            ]
        ),
        // Swift 层:uniFFI 生成的绑定
        .target(
            name: "CoolapkCoreSwift",
            dependencies: ["CoolapkCoreFFI"],
            path: "Sources/CoolapkCoreSwift",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // 原生 App
        .executableTarget(
            name: "CoolapkMac",
            dependencies: ["CoolapkCoreSwift"],
            path: "Sources/CoolapkMac",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CoolapkMacTests",
            dependencies: ["CoolapkCoreSwift", "CoolapkMac"],
            path: "Tests/CoolapkMacTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
