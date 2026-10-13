// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MonitorVolume",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MonitorVolume", targets: ["MonitorVolume"])],
    targets: [
        .target(name: "VolumeCore"),
        .target(name: "AppleSiliconDDCObjC", path: "Vendor/AppleSiliconDDCObjC", publicHeadersPath: "AppleSiliconDDC"),
        .target(name: "AppleSiliconDDC", dependencies: ["AppleSiliconDDCObjC"], path: "Vendor/AppleSiliconDDC",
                linkerSettings: [.linkedFramework("CoreDisplay")]),
        .executableTarget(name: "MonitorVolume", dependencies: ["VolumeCore", "AppleSiliconDDC"]),
        .testTarget(name: "VolumeCoreTests", dependencies: ["VolumeCore"])
    ]
)
