// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NegotoCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NegotoCore", targets: ["NegotoCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        .package(url: "https://github.com/facebook/zstd.git", from: "1.5.6"),
    ],
    targets: [
        // On Apple platforms the SDK's SQLite3 module is used instead.
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite", providers: [.apt(["libsqlite3-dev"])]),
        .target(
            name: "CStbVorbis",
            path: "Sources/CStbVorbis",
            exclude: ["stb_vorbis.inc"]
        ),
        .target(
            name: "NegotoCore",
            dependencies: [
                "ZIPFoundation",
                .product(name: "libzstd", package: "zstd"),
                .target(name: "CSQLite", condition: .when(platforms: [.linux])),
                "CStbVorbis",
            ]
        ),
        .testTarget(
            name: "NegotoCoreTests",
            dependencies: ["NegotoCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
