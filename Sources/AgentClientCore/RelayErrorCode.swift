import Foundation

public struct RelayErrorCode: Codable, Equatable {
    public let code: String

    // Auth
    public static let authMissing    = RelayErrorCode(code: "AUTH_MISSING")
    public static let authInvalid    = RelayErrorCode(code: "AUTH_INVALID")
    public static let authExpired    = RelayErrorCode(code: "AUTH_EXPIRED")

    // Pairing
    public static let claimAlreadyUsed = RelayErrorCode(code: "CLAIM_ALREADY_USED")
    public static let claimExpired     = RelayErrorCode(code: "CLAIM_EXPIRED")

    // Replay
    public static let replayRangeInvalid = RelayErrorCode(code: "REPLAY_RANGE_INVALID")

    // Commands
    public static let commandUnsupported = RelayErrorCode(code: "COMMAND_UNSUPPORTED")

    // General
    public static let generalError = RelayErrorCode(code: "GENERAL_ERROR")
}
