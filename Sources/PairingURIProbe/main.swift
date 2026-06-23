import AgentClientCore
import Foundation

// Test short URI
let uri = RelayPairingURI(host: "127.0.0.1", port: 48731, claim: "abc-def")
let uriStr = uri.uriString
guard uriStr.hasPrefix("macrelay://pair?") else { fatalError("uri prefix") }

// Parse back
guard let parsed = RelayPairingURI(from: uriStr) else { fatalError("parse uri") }
guard parsed.host == "127.0.0.1" else { fatalError("host") }
guard parsed.port == 48731 else { fatalError("port") }
guard parsed.claim == "abc-def" else { fatalError("claim") }

// Legacy JSON detect
let json = """
{"host":"127.0.0.1","port":48731,"token":"tk","claim":"cl","protocolVersion":1,"claimedAt":null,"expiresAt":"2026-08-01T00:00:00Z"}
"""
guard let detected = RelayPairingURI.detect(json) else { fatalError("detect json") }
guard detected.host == "127.0.0.1" else { fatalError("detect host") }
guard detected.claim == "cl" else { fatalError("detect claim") }
// Token should NOT be in the URI
guard !detected.uriString.contains("tk") else { fatalError("token leaked in uri") }

// Invalid inputs
guard RelayPairingURI(from: "not-a-uri") == nil else { fatalError("invalid") }
guard RelayPairingURI(from: "http://other") == nil else { fatalError("wrong scheme") }

print("PairingURIProbe passed uri+json+no-leak")
