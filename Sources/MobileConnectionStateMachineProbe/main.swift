import AgentClientCore
import Foundation

enum ProbeError: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let m): return m } }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw ProbeError.failed(message) }
}

let sm = MobileConnectionStateMachine()
var observed: [MobileStateTransition] = []
sm.onTransition = { observed.append($0) }

try expect(sm.state == .unpaired, "start unpaired")
try expect(sm.attemptPairing(), "pairing")
try expect(sm.state == .pairing, "state pairing")
try expect(sm.pairSuccess(), "pair ok")
try expect(sm.state == .paired, "state paired")
try expect(sm.startConnect(), "connecting")
try expect(sm.state == .connecting, "state connecting")
try expect(sm.connected(), "connected")
try expect(sm.state == .connected, "state connected")
try expect(sm.backoffAttempt == 0, "backoff reset")

try expect(sm.startReconnect(), "reconnecting")
try expect(sm.state == .reconnecting, "state reconnecting")
try expect(sm.backoffAttempt == 1, "backoff 1")
try expect(sm.connected(), "reconnect ok")
try expect(sm.backoffAttempt == 0, "backoff reset")

try expect(sm.networkLost(), "offline")
try expect(sm.state == .offline, "state offline")
try expect(sm.startReconnect(), "offline→reconnect")
try expect(sm.backoffAttempt == 1, "backoff from offline")

try expect(sm.authRejected(), "auth rejected")
try expect(sm.state == .authFailed, "authFailed")
try expect(sm.transition(to: .unpaired) != nil, "authFailed→unpaired")

try expect(sm.transition(to: .connected) == nil, "unpaired→connected invalid")
try expect(sm.transition(to: .offline) == nil, "unpaired→offline invalid")

try expect(sm.attemptPairing(), "pair again")
try expect(sm.pairFailed(), "pair failed")
try expect(sm.state == .unpaired, "back unpaired")

try expect(observed.count == 12, "12 transitions")
try expect(observed.first?.from == .unpaired && observed.first?.to == .pairing, "first transition")

print("MobileConnectionStateMachineProbe passed states=\(observed.count)")
