import Foundation

struct StudyDigest: Codable, Equatable {
    var createdAt: Date
    var patterns: [String]
    var rewrites: [DigestRewrite]
    var chineseToEnglish: [DigestPair]
    var drills: [String]
}

struct DigestRewrite: Codable, Equatable {
    var source: String
    var target: String
    var note: String
}

struct DigestPair: Codable, Equatable {
    var chinese: String
    var english: String
}

enum DeepSeekError: LocalizedError, Sendable {
    case missingKey
    case http(Int, String)
    case empty
    case truncated
    case badJSON
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "还没有 DeepSeek API Key。请在设置里填好后再截。"
        case .http(let code, let body):
            return "DeepSeek 返回 \(code)。\(body)"
        case .empty:
            return "模型没有返回内容。请再截一次。"
        case .truncated:
            return "模型输出被截断了。请把选区缩小到题目和回答后再试。"
        case .badJSON:
            return "模型没有返回可解析的 json。请再试一次。"
        case .transport(let message):
            return "网络请求失败：\(message)"
        }
    }
}

struct DeepSeekClient: Sendable {
    var apiKey: String
    var model: String
    var session: URLSession

    init(apiKey: String, model: String, session: URLSession = DeepSeekClient.makeSession()) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 180
        return URLSession(configuration: config)
    }

    func analyze(imageJPEG: Data) async throws -> (payload: ReviewPayload, raw: String) {
        let first = try await complete(
            userParts: [
                .text(Prompt.user),
                .imageJPEG(imageJPEG),
            ]
        )
        if let payload = try? ReviewParser.parse(first) {
            return (payload, first)
        }
        let second = try await complete(
            userParts: [
                .text(Prompt.retryUser(previous: first)),
                .imageJPEG(imageJPEG),
            ]
        )
        do {
            return (try ReviewParser.parse(second), second)
        } catch {
            throw DeepSeekError.badJSON
        }
    }

    func digest(prompt: String) async throws -> StudyDigest {
        let raw = try await complete(system: Prompt.digestSystem, userParts: [.text(prompt)])
        let parsed = try parseDigest(raw)
        return parsed
    }

    func followUp(correction: String, prior: [FollowUpTurn], question: String) async throws -> String {
        var messages: [ChatMessage] = [
            ChatMessage(role: "system", content: .text(Prompt.followUp)),
            ChatMessage(role: "user", content: .text("这一次纠正的内容如下：\n\(correction)")),
        ]
        for turn in prior {
            let role = turn.role == "assistant" ? "assistant" : "user"
            messages.append(ChatMessage(role: role, content: .text(turn.text)))
        }
        messages.append(ChatMessage(role: "user", content: .text(question)))
        return try await post(messages: messages, json: false, maxTokens: 1200, temperature: 0.3)
    }

    func complete(system: String = Prompt.system, userParts: [ContentPart]) async throws -> String {
        try await post(
            messages: [
                ChatMessage(role: "system", content: .text(system)),
                ChatMessage(role: "user", content: .parts(userParts)),
            ],
            json: true,
            maxTokens: 4096,
            temperature: 0.2
        )
    }

    private func post(messages: [ChatMessage], json: Bool, maxTokens: Int, temperature: Double) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body = ChatRequest(
            model: model,
            messages: messages,
            responseFormat: json ? ResponseFormat(type: "json_object") : nil,
            thinking: Thinking(type: "disabled"),
            maxTokens: maxTokens,
            temperature: temperature
        )
        request.httpBody = try JSONEncoder().encode(body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DeepSeekError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.transport("没有 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(400) ?? ""
            throw DeepSeekError.http(http.statusCode, String(snippet))
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let choice = decoded.choices.first
        let content = choice?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if content.isEmpty || content.allSatisfy({ $0 == " " }) {
            if choice?.finishReason == "length" {
                throw DeepSeekError.truncated
            }
            throw DeepSeekError.empty
        }
        return content
    }

    private func parseDigest(_ text: String) throws -> StudyDigest {
        let sliced = ReviewParser.extractJSONObject(text)
        guard let data = sliced.data(using: .utf8) else { throw DeepSeekError.badJSON }
        let dto: DigestDTO
        do {
            dto = try JSONDecoder().decode(DigestDTO.self, from: data)
        } catch {
            throw DeepSeekError.badJSON
        }
        return StudyDigest(
            createdAt: Date(),
            patterns: dto.patterns ?? [],
            rewrites: (dto.rewrites ?? []).map {
                DigestRewrite(source: $0.source ?? "", target: $0.target ?? "", note: $0.note ?? "")
            },
            chineseToEnglish: (dto.chineseToEnglish ?? []).map {
                DigestPair(chinese: $0.chinese ?? "", english: $0.english ?? "")
            },
            drills: dto.drills ?? []
        )
    }
}

enum ContentPart: Encodable {
    case text(String)
    case imageJPEG(Data)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageJPEG(let data):
            try container.encode("image_url", forKey: .type)
            var image = container.nestedContainer(keyedBy: ImageKeys.self, forKey: .imageURL)
            try image.encode("data:image/jpeg;base64,\(data.base64EncodedString())", forKey: .url)
            try image.encode("original", forKey: .detail)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    private enum ImageKeys: String, CodingKey {
        case url
        case detail
    }
}

private struct ChatRequest: Encodable {
    var model: String
    var messages: [ChatMessage]
    var responseFormat: ResponseFormat?
    var thinking: Thinking
    var maxTokens: Int
    var temperature: Double

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case responseFormat = "response_format"
        case thinking
        case maxTokens = "max_tokens"
        case temperature
    }
}

private struct ResponseFormat: Encodable {
    var type: String
}

private struct Thinking: Encodable {
    var type: String
}

private struct ChatMessage: Encodable {
    var role: String
    var content: MessageContent
}

private enum MessageContent: Encodable {
    case text(String)
    case parts([ContentPart])

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let text):
            var container = encoder.singleValueContainer()
            try container.encode(text)
        case .parts(let parts):
            var container = encoder.singleValueContainer()
            try container.encode(parts)
        }
    }
}

private struct ChatResponse: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var message: Message
        var finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct Message: Decodable {
        var content: String?
    }
}

private struct DigestDTO: Decodable {
    var patterns: [String]?
    var rewrites: [RewriteDTO]?
    var chineseToEnglish: [PairDTO]?
    var drills: [String]?

    enum CodingKeys: String, CodingKey {
        case patterns
        case rewrites
        case chineseToEnglish = "chinese_to_english"
        case drills
    }
}

private struct RewriteDTO: Decodable {
    var source: String?
    var target: String?
    var note: String?
}

private struct PairDTO: Decodable {
    var chinese: String?
    var english: String?
}
