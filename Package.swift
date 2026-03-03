// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SQLSwiftUIPackage",
    platforms: [.macOS(.v26),
    .iOS(.v26),
    .tvOS(.v26),
    .watchOS(.v26)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SQLDataAccess",
            targets: ["SQLDataAccess"]),
        .library(
        name: "DataManager",
        targets: ["DataManager"]),
        .library(
        name: "Sqldb",
        targets: ["Sqldb"]),
        .library(
        name: "SQLExtensions",
        targets: ["SQLExtensions"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        //.package(url: "git@github.com:apple/swift-log.git", from: "1.4.0"),
        .package(url: "git@github.com:Nike-Inc/Willow.git", from: "6.0.0"),
        .package(url: "git@github.com:tristanhimmelman/ObjectMapper.git", from: "4.2.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SQLDataAccess",
            dependencies: [.product(name:"Willow", package:"Willow"),"ObjectMapper"],path:"Sources/SQLDataAccess"),
        .target(name:"DataManager",
            dependencies:["SQLDataAccess"],
            path:"Sources/DataManager"),
        .target(name:"Sqldb",
            dependencies:[],
            path:"Sources/Sqldb"),
        .target(name:"SQLExtensions",
            dependencies:["DataManager"],
            path:"Sources/SQLExtensions"),
        .testTarget(
            name: "SQLSwiftUIPackageTests",
            dependencies: ["SQLDataAccess"],
            path:"Tests/SQLSwiftUIPackageTests"),
    ]
)
