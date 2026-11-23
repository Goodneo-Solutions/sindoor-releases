// swift-tools-version:5.9
// sIndoor for iOS and macOS: SIndoor (the engine on the device, sensors, BLE beacons) and SIndoorMap (the navigation
// screen on sMap's SMapView). Documentation: https://open.superroute.ca/developer
import PackageDescription

let package = Package(
    name: "SIndoor",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "SIndoor", targets: ["SIndoor"]),
        .library(name: "SIndoorMap", targets: ["SIndoorMap"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Goodneo-Solutions/smap-sdk-releases", from: "1.6.5"),
    ],
    targets: [
        .binaryTarget(
            name: "SindoorFFI",
            url: "https://github.com/Goodneo-Solutions/sindoor-releases/releases/download/0.1.0/SindoorFFI.xcframework.zip",
            checksum: "fea128aeace94f0bb276357be25ca186c7b3fa65757982bab2f72142c9906e5b"
        ),
        .target(
            name: "SIndoor",
            dependencies: ["SindoorFFI"],
            path: "Sources/SIndoor",
            linkerSettings: [
                .linkedFramework("CoreLocation"),
                .linkedFramework("CoreMotion", .when(platforms: [.iOS])),
                .linkedFramework("CoreBluetooth", .when(platforms: [.iOS])),
            ]
        ),
        .target(
            name: "SIndoorMap",
            dependencies: ["SIndoor", .product(name: "SMap", package: "smap-sdk-releases")],
            path: "Sources/SIndoorMap"
        ),
    ]
)
