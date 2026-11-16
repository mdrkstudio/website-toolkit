// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "WebsiteToolkit", platforms: [.macOS(.v13)], products: [.library(name: "WebsiteToolkit", targets: ["WebsiteToolkit"]), .executable(name: "website-inspect", targets: ["WebsiteInspect"])], targets: [.target(name: "WebsiteToolkit"), .executableTarget(name: "WebsiteInspect", dependencies: ["WebsiteToolkit"])])
