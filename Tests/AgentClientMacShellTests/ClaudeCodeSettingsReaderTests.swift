import XCTest
@testable import AgentClientMacShell

final class ClaudeCodeSettingsReaderTests: XCTestCase {
    func test_readsDeepSeekModelsFromClaudeSettingsEnv() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeCodeSettingsReaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settingsURL = directory.appendingPathComponent("settings.json")
        let json = """
        {
          "env": {
            "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
            "ANTHROPIC_MODEL": "deepseek-v4-flash",
            "ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-v4-pro[1M]",
            "ANTHROPIC_DEFAULT_SONNET_MODEL": "deepseek-v4-flash[1M]",
            "ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-v4-flash",
            "ANTHROPIC_SMALL_FAST_MODEL": "deepseek-reasoner"
          },
          "model": "sonnet"
        }
        """
        try json.data(using: .utf8)?.write(to: settingsURL)

        let models = ClaudeCodeSettingsReader.readModelNames(paths: [settingsURL.path])

        XCTAssertEqual(models, [
            "deepseek-v4-flash",
            "deepseek-v4-pro[1M]",
            "deepseek-v4-flash[1M]",
            "deepseek-reasoner"
        ])
    }

    func test_fallsBackWhenNoSettingsContainModels() {
        let models = ClaudeCodeSettingsReader.readModelNames(paths: ["/path/that/does/not/exist"])

        XCTAssertEqual(models, ["claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5"])
    }
}
