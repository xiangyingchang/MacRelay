import Foundation

// MARK: - OpenAI Compatible Client

/// HTTP client for OpenAI-compatible chat completion APIs.
///
/// Supports:
/// - Streaming SSE responses
/// - Tool calling (function calling)
/// - Multiple providers (OpenAI, DeepSeek, MIMO, etc.)
public final class OpenAICompatibleClient: @unchecked Sendable {
    private let provider: APIProvider
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(provider: APIProvider) {
        self.provider = provider

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
    }

    // MARK: - Chat Completion Request

    /// Send a chat completion request with streaming support.
    public func chatCompletion(
        messages: [ChatMessage],
        model: String?,
        tools: [ToolDefinition]?,
        stream: Bool = true
    ) async throws -> AsyncThrowingStream<ChatCompletionChunk, Error> {
        let request = try buildRequest(
            messages: messages,
            model: model ?? provider.defaultModel ?? "gpt-4o",
            tools: tools,
            stream: stream
        )

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let errorResponse = try? decoder.decode(ErrorResponse.self, from: errorData)
            throw APIError.httpError(
                statusCode: httpResponse.statusCode,
                message: errorResponse?.error.message ?? String(data: errorData, encoding: .utf8) ?? "Unknown error"
            )
        }

        if stream {
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        var buffer = ""
                        for try await byte in bytes {
                            let char = Character(UnicodeScalar(byte))
                            buffer.append(char)

                            // Process complete lines
                            while let newlineIndex = buffer.firstIndex(of: "\n") {
                                let line = String(buffer[buffer.startIndex...newlineIndex])
                                buffer = String(buffer[buffer.index(after: newlineIndex)...])

                                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                                if trimmed.isEmpty { continue }
                                if trimmed == "data: [DONE]" {
                                    continuation.finish()
                                    return
                                }

                                if trimmed.hasPrefix("data: ") {
                                    let jsonString = String(trimmed.dropFirst(6))
                                    if let data = jsonString.data(using: .utf8),
                                       let chunk = try? self.decoder.decode(ChatCompletionChunk.self, from: data) {
                                        continuation.yield(chunk)
                                    }
                                }
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        } else {
            // Non-streaming: collect all bytes and decode
            var allData = Data()
            for try await byte in bytes {
                allData.append(byte)
            }
            let response = try decoder.decode(ChatCompletionResponse.self, from: allData)
            return AsyncThrowingStream { continuation in
                // Convert non-streaming response to a single chunk
                if let choice = response.choices.first {
                    let chunk = ChatCompletionChunk(
                        id: response.id,
                        choices: [
                            ChatCompletionChunk.ChunkChoice(
                                index: 0,
                                delta: ChatCompletionChunk.ChoiceDelta(
                                    role: "assistant",
                                    content: choice.message.content,
                                    toolCalls: choice.message.toolCalls
                                ),
                                finishReason: choice.finishReason
                            )
                        ]
                    )
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Build Request

    private func buildRequest(
        messages: [ChatMessage],
        model: String,
        tools: [ToolDefinition]?,
        stream: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: "\(provider.baseURL)/chat/completions") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { $0.toDictionary() },
            "stream": stream
        ]

        if let tools, !tools.isEmpty, provider.supportsToolCalling {
            body["tools"] = tools.map { $0.toDictionary() }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

// MARK: - Chat Message

/// A message in the OpenAI chat completion format.
public struct ChatMessage: Codable {
    public let role: String
    public let content: String?
    public let toolCalls: [ToolCall]?
    public let toolCallId: String?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }

    public init(role: String, content: String?, toolCalls: [ToolCall]? = nil, toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["role": role]
        if let content { dict["content"] = content }
        if let toolCalls { dict["tool_calls"] = toolCalls.map { $0.toDictionary() } }
        if let toolCallId { dict["tool_call_id"] = toolCallId }
        return dict
    }
}

// MARK: - Tool Definition

/// Definition of a tool that can be called by the model.
public struct ToolDefinition: Codable {
    public let type: String
    public let function: FunctionDefinition

    public init(function: FunctionDefinition) {
        self.type = "function"
        self.function = function
    }

    public func toDictionary() -> [String: Any] {
        [
            "type": type,
            "function": function.toDictionary()
        ]
    }
}

/// Definition of a function tool.
public struct FunctionDefinition: Codable {
    public let name: String
    public let description: String
    public let parameters: [String: Any]

    enum CodingKeys: String, CodingKey {
        case name, description, parameters
    }

    public init(name: String, description: String, parameters: [String: Any]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        let paramsData = try container.decode(AnyCodable.self, forKey: .parameters)
        parameters = paramsData.value as? [String: Any] ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(AnyCodable(parameters), forKey: .parameters)
    }

    public func toDictionary() -> [String: Any] {
        [
            "name": name,
            "description": description,
            "parameters": parameters
        ]
    }
}

// MARK: - Tool Call

/// A tool call made by the model.
public struct ToolCall: Codable {
    public let id: String
    public let type: String
    public let function: FunctionCall

    public init(id: String, type: String = "function", function: FunctionCall) {
        self.id = id
        self.type = type
        self.function = function
    }

    public func toDictionary() -> [String: Any] {
        [
            "id": id,
            "type": type,
            "function": function.toDictionary()
        ]
    }
}

/// A function call within a tool call.
public struct FunctionCall: Codable {
    public let name: String
    public let arguments: String

    public init(name: String, arguments: String) {
        self.name = name
        self.arguments = arguments
    }

    public func toDictionary() -> [String: Any] {
        [
            "name": name,
            "arguments": arguments
        ]
    }
}

// MARK: - Chat Completion Response (Non-streaming)

public struct ChatCompletionResponse: Codable {
    public let id: String
    public let object: String
    public let created: Int
    public let model: String
    public let choices: [Choice]
    public let usage: Usage?

    public struct Choice: Codable {
        public let index: Int
        public let message: AssistantMessage
        public let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }

    public struct AssistantMessage: Codable {
        public let role: String
        public let content: String?
        public let toolCalls: [ToolCall]?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
        }
    }

    public struct Usage: Codable {
        public let promptTokens: Int
        public let completionTokens: Int
        public let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

// MARK: - Chat Completion Chunk (Streaming)

public struct ChatCompletionChunk: Codable {
    public let id: String
    public let choices: [ChunkChoice]

    public struct ChunkChoice: Codable {
        public let index: Int
        public let delta: ChoiceDelta
        public let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, delta
            case finishReason = "finish_reason"
        }
    }

    public struct ChoiceDelta: Codable {
        public let role: String?
        public let content: String?
        public let toolCalls: [ToolCall]?

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCalls = "tool_calls"
        }
    }
}

// MARK: - Error Response

public struct ErrorResponse: Codable {
    public let error: ErrorDetail

    public struct ErrorDetail: Codable {
        public let message: String
        public let type: String?
        public let code: String?
    }
}

// MARK: - API Error

public enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid API response"
        case .httpError(let code, let msg):
            return "API error (\(code)): \(msg)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }
}

// MARK: - AnyCodable Helper

/// Helper for encoding/decoding Any values.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let string = value as? String {
            try container.encode(string)
        } else if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodable($0) })
        } else {
            try container.encodeNil()
        }
    }
}
