import Foundation

// MARK: - API Provider Configuration

/// Configuration for an OpenAI-compatible API provider.
///
/// This struct holds the connection details and capabilities for
/// providers like OpenAI, DeepSeek, MIMO, and other OpenAI-compatible endpoints.
public struct APIProvider: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let baseURL: String
    public let apiKey: String
    public let defaultModel: String?
    public let supportsStreaming: Bool
    public let supportsToolCalling: Bool
    public let supportsVision: Bool
    public let protocolType: ProtocolType

    public enum ProtocolType: String, Codable {
        case openai          // Standard OpenAI chat completions
        case openaiCompat    // OpenAI-compatible endpoint (DeepSeek, MIMO, etc.)
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        baseURL: String,
        apiKey: String,
        defaultModel: String? = nil,
        supportsStreaming: Bool = true,
        supportsToolCalling: Bool = true,
        supportsVision: Bool = false,
        protocolType: ProtocolType = .openai
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.defaultModel = defaultModel
        self.supportsStreaming = supportsStreaming
        self.supportsToolCalling = supportsToolCalling
        self.supportsVision = supportsVision
        self.protocolType = protocolType
    }
}

// MARK: - Built-in Providers

extension APIProvider {
    /// OpenAI API provider.
    public static let openAI = APIProvider(
        id: "openai",
        name: "OpenAI",
        baseURL: "https://api.openai.com/v1",
        apiKey: "",  // User must configure
        defaultModel: "gpt-4o",
        supportsStreaming: true,
        supportsToolCalling: true,
        supportsVision: true,
        protocolType: .openai
    )

    /// DeepSeek API provider.
    public static let deepSeek = APIProvider(
        id: "deepseek",
        name: "DeepSeek",
        baseURL: "https://api.deepseek.com/v1",
        apiKey: "",  // User must configure
        defaultModel: "deepseek-chat",
        supportsStreaming: true,
        supportsToolCalling: true,
        supportsVision: false,
        protocolType: .openaiCompat
    )

    /// MIMO API provider.
    public static let mimo = APIProvider(
        id: "mimo",
        name: "MIMO",
        baseURL: "https://api.mimo.com/v1",
        apiKey: "",  // User must configure
        defaultModel: "mimo-chat",
        supportsStreaming: true,
        supportsToolCalling: true,
        supportsVision: false,
        protocolType: .openaiCompat
    )
}

// MARK: - Provider Store

/// Stores configured API providers with API keys in Keychain.
///
/// Provider metadata (name, baseURL, model, etc.) is stored in UserDefaults.
/// API keys are stored separately in Keychain for security.
public final class APIProviderStore: @unchecked Sendable {
    private static let userDefaultsKey = "configuredAPIProviders"
    private static let keychainService = "com.macrelay.apikeys"

    public init() {}

    // MARK: - Public API

    /// Load all configured providers.
    public func loadProviders() -> [APIProvider] {
        guard let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
              let metadata = try? JSONDecoder().decode([ProviderMetadata].self, from: data) else {
            return []
        }

        return metadata.compactMap { meta in
            let apiKey = loadAPIKey(for: meta.id) ?? ""
            return APIProvider(
                id: meta.id,
                name: meta.name,
                baseURL: meta.baseURL,
                apiKey: apiKey,
                defaultModel: meta.defaultModel,
                supportsStreaming: meta.supportsStreaming,
                supportsToolCalling: meta.supportsToolCalling,
                supportsVision: meta.supportsVision,
                protocolType: meta.protocolType
            )
        }
    }

    /// Save a provider configuration.
    public func saveProvider(_ provider: APIProvider) {
        var metadata = loadMetadata()
        let newMeta = ProviderMetadata(from: provider)

        if let index = metadata.firstIndex(where: { $0.id == provider.id }) {
            metadata[index] = newMeta
        } else {
            metadata.append(newMeta)
        }

        // Save metadata to UserDefaults
        if let data = try? JSONEncoder().encode(metadata) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }

        // Save API key to Keychain
        saveAPIKey(provider.apiKey, for: provider.id)
    }

    /// Delete a provider configuration.
    public func deleteProvider(id: String) {
        var metadata = loadMetadata()
        metadata.removeAll { $0.id == id }

        // Remove metadata from UserDefaults
        if let data = try? JSONEncoder().encode(metadata) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }

        // Remove API key from Keychain
        deleteAPIKey(for: id)
    }

    // MARK: - Private: Metadata (UserDefaults)

    /// Provider metadata without sensitive fields.
    private struct ProviderMetadata: Codable, Equatable {
        let id: String
        let name: String
        let baseURL: String
        let defaultModel: String?
        let supportsStreaming: Bool
        let supportsToolCalling: Bool
        let supportsVision: Bool
        let protocolType: APIProvider.ProtocolType

        init(from provider: APIProvider) {
            self.id = provider.id
            self.name = provider.name
            self.baseURL = provider.baseURL
            self.defaultModel = provider.defaultModel
            self.supportsStreaming = provider.supportsStreaming
            self.supportsToolCalling = provider.supportsToolCalling
            self.supportsVision = provider.supportsVision
            self.protocolType = provider.protocolType
        }
    }

    private func loadMetadata() -> [ProviderMetadata] {
        guard let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
              let metadata = try? JSONDecoder().decode([ProviderMetadata].self, from: data) else {
            return []
        }
        return metadata
    }

    // MARK: - Private: API Keys (Keychain)

    private func loadAPIKey(for providerID: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: providerID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private func saveAPIKey(_ apiKey: String, for providerID: String) {
        guard let data = apiKey.data(using: .utf8) else { return }

        // Delete existing item
        deleteAPIKey(for: providerID)

        // Add new item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: providerID,
            kSecValueData as String: data
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    private func deleteAPIKey(for providerID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: providerID
        ]

        SecItemDelete(query as CFDictionary)
    }
}
