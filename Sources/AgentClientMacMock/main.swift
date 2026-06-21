import AgentClientCore
import Foundation

let payload = MockSnapshotFactory.makeRelaySnapshot()
let data = try JSONEncoder().encode(RelayEnvelope(type: RelayEventType.snapshot.rawValue, payload: payload))
let object = try JSONSerialization.jsonObject(with: data)
let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
print(String(data: pretty, encoding: .utf8) ?? "{}")
