// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AgentClientM1Prototype",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "AgentClientCore", targets: ["AgentClientCore"]),
        .library(name: "AgentClientIO", targets: ["AgentClientIO"]),
        .library(name: "AgentClientiOS", targets: ["AgentClientiOS"]),
        .executable(name: "AgentClientMacMock", targets: ["AgentClientMacMock"]),
        .executable(name: "AgentClientMacShell", targets: ["AgentClientMacShell"]),
        .executable(name: "CodexAppServerInitProbe", targets: ["CodexAppServerInitProbe"]),
        .executable(name: "CodexDetectorProbe", targets: ["CodexDetectorProbe"]),
        .executable(name: "RelayCommandFixtureProbe", targets: ["RelayCommandFixtureProbe"]),
        .executable(name: "RelayCoreFixtureProbe", targets: ["RelayCoreFixtureProbe"]),
        .executable(name: "MacRelayServiceFixtureProbe", targets: ["MacRelayServiceFixtureProbe"]),
        .executable(name: "MacRelayHTTPServerProbe", targets: ["MacRelayHTTPServerProbe"]),
        .executable(name: "MacRelayWebSocketServerProbe", targets: ["MacRelayWebSocketServerProbe"]),
        .executable(name: "RelayRuntimeCommandDispatcherProbe", targets: ["RelayRuntimeCommandDispatcherProbe"]),
        .executable(name: "RelayCommandLiveProbe", targets: ["RelayCommandLiveProbe"]),
        .executable(name: "PairingCredentialStoreFixtureProbe", targets: ["PairingCredentialStoreFixtureProbe"]),
        .executable(name: "KeychainPairingCredentialStoreProbe", targets: ["KeychainPairingCredentialStoreProbe"]),
        .executable(name: "DeviceTrustStoreProbe", targets: ["DeviceTrustStoreProbe"]),
        .executable(name: "iPhoneSimClientProbe", targets: ["iPhoneSimClientProbe"]),
        .executable(name: "AgentClientIOProbe", targets: ["AgentClientIOProbe"]),
        .executable(name: "RealStateMachineLoopProbe", targets: ["RealStateMachineLoopProbe"]),
        .executable(name: "RelayApprovalLiveProbe", targets: ["RelayApprovalLiveProbe"]),
        .executable(name: "MobileConnectionStateMachineProbe", targets: ["MobileConnectionStateMachineProbe"]),
        .executable(name: "SandboxPayloadProbe", targets: ["SandboxPayloadProbe"]),
        .executable(name: "ThreadStartSchemaProbe", targets: ["ThreadStartSchemaProbe"]),
        .executable(name: "TurnStartSchemaProbe", targets: ["TurnStartSchemaProbe"]),
        .executable(name: "TurnEventTraceProbe", targets: ["TurnEventTraceProbe"]),
        .executable(name: "SettingsUpdateSchemaProbe", targets: ["SettingsUpdateSchemaProbe"]),
        .executable(name: "SettingsUpdateLiveProbe", targets: ["SettingsUpdateLiveProbe"])
    ],
    targets: [
        .target(name: "AgentClientCore"),
        .target(
            name: "AgentClientIO",
            dependencies: ["AgentClientCore"]
        ),
        .target(
            name: "AgentClientiOS",
            dependencies: ["AgentClientCore", "AgentClientIO"]
        ),
        .executableTarget(
            name: "AgentClientMacMock",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "AgentClientMacShell",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "CodexAppServerInitProbe",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "CodexDetectorProbe",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "RelayCommandFixtureProbe",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "RelayCoreFixtureProbe",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "MacRelayServiceFixtureProbe",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "MacRelayHTTPServerProbe",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "MacRelayWebSocketServerProbe",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "RelayRuntimeCommandDispatcherProbe",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "RelayCommandLiveProbe",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "PairingCredentialStoreFixtureProbe",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "KeychainPairingCredentialStoreProbe",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "DeviceTrustStoreProbe",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "iPhoneSimClientProbe",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "AgentClientIOProbe",
            dependencies: ["AgentClientCore", "AgentClientIO"]
        ),
        .executableTarget(
            name: "RealStateMachineLoopProbe",
            dependencies: ["AgentClientCore", "AgentClientIO"]
        ),
        .executableTarget(
            name: "RelayApprovalLiveProbe",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "MobileConnectionStateMachineProbe",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "SandboxPayloadProbe"
        ),
        .executableTarget(
            name: "ThreadStartSchemaProbe",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "TurnStartSchemaProbe",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "TurnEventTraceProbe",
            dependencies: ["AgentClientCore"]
        ),
        .executableTarget(
            name: "SettingsUpdateSchemaProbe"
        ),
        .executableTarget(
            name: "SettingsUpdateLiveProbe",
            dependencies: ["AgentClientCore"]
        ),
        .testTarget(
            name: "AgentClientCoreTests",
            dependencies: ["AgentClientCore"]
        )
    ]
)
