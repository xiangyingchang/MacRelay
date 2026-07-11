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

/// Stores configured API providers in UserDefaults.
public final class APIProviderStore: @unchecked Sendable {
    private let key = "configuredAPIProviders"

    public init() {}

    /// Load all configured providers.
    public func loadProviders() -> [APIProvider] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let providers = try? JSONDecoder().decode([APIProvider].self, from: data) else {
            return []
        }
        return providers
    }

    /// Save a provider configuration.
    public func saveProvider(_ provider: APIProvider) {
        var providers = loadProviders()
        if let index = providers.firstIndex(where: { $0.id == provider.id }) {
            providers[index] = provider
        } else {
            providers.append(provider)
        }
        if let data = try? JSONEncoder().encode(providers) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Delete a provider configuration.
    public func deleteProvider(id: String) {
        var providers = loadProviders()
        providers.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(providers) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
