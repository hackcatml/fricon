// swift-tools-version:5.6

import PackageDescription
import Foundation

struct Theos {
    let path: String
    let resources: String
    let sdk: String
    let target: String
    
    init() {
        let configURL: URL = .init(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent(".theos")
            .appendingPathComponent("spm_config")
        
        guard let data: Data = try? .init(contentsOf: configURL),
              let lines: [String] = String(data: data, encoding: .utf8)?.components(separatedBy: "\n"),
              let tmpPath: String = lines[0].components(separatedBy: "=").last,
              let tmpSdk: String = lines[1].components(separatedBy: "=").last,
              let tmpTarget: String = lines[2].components(separatedBy: "=").last,
              let tmpResources: String = lines[3].components(separatedBy: "=").last
        else {
            path = ("~/theos" as NSString).expandingTildeInPath
            resources = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/../lib/swift"
            sdk = path + "/sdks/iPhoneOS16.2.sdk/"
            target = "12.2"
            
            return
        }
        
        path = tmpPath
        resources = tmpResources
        sdk = tmpSdk
        target = tmpTarget
    }
}

let theos: Theos = .init()
let theosPath: String = theos.path

let swiftFlags: [String] = [
    "-F\(theosPath)/vendor/lib",
    "-F\(theosPath)/lib",
    "-I\(theosPath)/vendor/include",
    "-I\(theosPath)/include",
    "-target", "arm64-apple-ios\(theos.target)",
    "-sdk", theos.sdk,
    "-resource-dir", theos.resources
]

let package: Package = .init(
    name: "friconswift",
    platforms: [.iOS(theos.target)],
    products: [
        .library(
            name: "friconswift",
            targets: ["friconswift"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/dmulholl/argparser.git", branch: "master"),
    ],
    targets: [
        .target(
            name: "friconswift",
            dependencies: [.product(name: "ArgParser", package: "ArgParser")],
            swiftSettings: [.unsafeFlags(swiftFlags)]
        )
    ]
)
