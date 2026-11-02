import Foundation

enum AnswerLanguage: String, Codable, Equatable {
    case en
    case zh
    case mixed
}

struct AnswerError: Codable, Equatable, Identifiable {
    var id: UUID
    var excerpt: String
    var kind: String
    var problem: String
    var fix: String
    var mastered: Bool
}

struct Answer: Codable, Equatable, Identifiable {
    var id: UUID
    var question: String
    var userAnswer: String
    var answerLanguage: AnswerLanguage
    var errors: [AnswerError]
    var natural: String
    var alternative: String
    var mastered: Bool
}

struct ReviewPayload: Codable, Equatable {
    var answers: [Answer]
    var summary: String
}

struct FollowUpTurn: Codable, Equatable, Identifiable {
    var id: UUID
    var role: String
    var text: String
}

struct ReviewSession: Codable, Equatable, Identifiable {
    var id: UUID
    var createdAt: Date
    var imageFilename: String
    var rawJSON: String
    var payload: ReviewPayload
    var oversized: Bool
    var followUps: [FollowUpTurn]

    init(
        id: UUID,
        createdAt: Date,
        imageFilename: String,
        rawJSON: String,
        payload: ReviewPayload,
        oversized: Bool,
        followUps: [FollowUpTurn] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.imageFilename = imageFilename
        self.rawJSON = rawJSON
        self.payload = payload
        self.oversized = oversized
        self.followUps = followUps
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, imageFilename, rawJSON, payload, oversized, followUps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        imageFilename = try container.decode(String.self, forKey: .imageFilename)
        rawJSON = try container.decode(String.self, forKey: .rawJSON)
        payload = try container.decode(ReviewPayload.self, forKey: .payload)
        oversized = try container.decode(Bool.self, forKey: .oversized)
        followUps = try container.decodeIfPresent([FollowUpTurn].self, forKey: .followUps) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(imageFilename, forKey: .imageFilename)
        try container.encode(rawJSON, forKey: .rawJSON)
        try container.encode(payload, forKey: .payload)
        try container.encode(oversized, forKey: .oversized)
        try container.encode(followUps, forKey: .followUps)
    }
}

enum NaturalCopy {
    static func text(from payload: ReviewPayload) -> String {
        payload.answers
            .map { $0.natural.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum FollowUpContext {
    static func make(_ session: ReviewSession) -> String {
        var lines: [String] = []
        if !session.payload.summary.isEmpty {
            lines.append("总评：\(session.payload.summary)")
        }
        for (index, answer) in session.payload.answers.enumerated() {
            lines.append("第 \(index + 1) 条")
            if !answer.question.isEmpty {
                lines.append("题目：\(answer.question)")
            }
            lines.append("用户回答：\(answer.userAnswer)")
            if !answer.natural.isEmpty {
                lines.append("地道英文：\(answer.natural)")
            }
            if !answer.alternative.isEmpty {
                lines.append("另一种说法：\(answer.alternative)")
            }
            for error in answer.errors {
                lines.append(
                    "问题[\(ErrorKind.label(error.kind))]：\(error.problem) 片段「\(error.excerpt)」建议「\(error.fix)」"
                )
            }
        }
        return lines.joined(separator: "\n")
    }
}

enum ReviewParseError: Error, Equatable {
    case empty
    case invalidJSON
}

enum ErrorKind {
    static let all = [
        "grammar", "tense", "article", "preposition", "agreement",
        "word_choice", "collocation", "spelling", "punctuation",
        "unnatural", "incomplete", "mixed_language", "other",
    ]

    static let labels: [String: String] = [
        "grammar": "语法",
        "tense": "时态",
        "article": "冠词",
        "preposition": "介词",
        "agreement": "一致",
        "word_choice": "用词",
        "collocation": "搭配",
        "spelling": "拼写",
        "punctuation": "标点",
        "unnatural": "不地道",
        "incomplete": "不完整",
        "mixed_language": "中英夹杂",
        "other": "其他",
    ]

    static func normalize(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return all.contains(key) ? key : "other"
    }

    static func label(_ kind: String) -> String {
        labels[normalize(kind)] ?? "其他"
    }
}

enum ReviewParser {
    static func parse(_ text: String) throws -> ReviewPayload {
        let sliced = extractJSONObject(text)
        guard !sliced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReviewParseError.empty
        }
        guard let data = sliced.data(using: .utf8) else {
            throw ReviewParseError.invalidJSON
        }
        let dto: PayloadDTO
        do {
            dto = try JSONDecoder().decode(PayloadDTO.self, from: data)
        } catch {
            throw ReviewParseError.invalidJSON
        }
        let answers = (dto.answers ?? []).map(makeAnswer)
        return ReviewPayload(answers: answers, summary: dto.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    static func extractJSONObject(_ text: String) -> String {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("```") {
            if let firstLine = raw.firstIndex(of: "\n") {
                raw = String(raw[raw.index(after: firstLine)...])
            }
            if let fence = raw.range(of: "```", options: .backwards) {
                raw = String(raw[..<fence.lowerBound])
            }
            raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start <= end else {
            return raw
        }
        return String(raw[start...end])
    }

    private static func makeAnswer(_ dto: AnswerDTO) -> Answer {
        let userAnswer = dto.userAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = normalizeLanguage(dto.answerLanguage, userAnswer: userAnswer)
        var errors = (dto.errors ?? []).map { error in
            AnswerError(
                id: UUID(),
                excerpt: error.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                kind: ErrorKind.normalize(error.kind ?? ""),
                problem: error.problem?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                fix: error.fix?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                mastered: false
            )
        }
        if language == .zh {
            errors = []
        }
        return Answer(
            id: UUID(),
            question: dto.question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            userAnswer: userAnswer,
            answerLanguage: language,
            errors: errors,
            natural: dto.natural?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            alternative: dto.alternative?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            mastered: false
        )
    }

    static func normalizeLanguage(_ raw: String?, userAnswer: String) -> AnswerLanguage {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "en":
            return .en
        case "zh":
            return .zh
        case "mixed":
            return .mixed
        default:
            return inferLanguage(userAnswer)
        }
    }

    static func inferLanguage(_ text: String) -> AnswerLanguage {
        let hasCJK = text.unicodeScalars.contains { scalar in
            let value = Int(scalar.value)
            return (0x3400...0x9FFF).contains(value)
        }
        let hasLatin = text.unicodeScalars.contains { scalar in
            let value = Int(scalar.value)
            return (65...90).contains(value) || (97...122).contains(value)
        }
        if hasCJK && hasLatin { return .mixed }
        if hasCJK { return .zh }
        return .en
    }
}

private struct PayloadDTO: Decodable {
    var answers: [AnswerDTO]?
    var summary: String?
}

private struct AnswerDTO: Decodable {
    var question: String?
    var userAnswer: String
    var answerLanguage: String?
    var errors: [ErrorDTO]?
    var natural: String?
    var alternative: String?

    enum CodingKeys: String, CodingKey {
        case question
        case userAnswer = "user_answer"
        case userAnswerCamel = "userAnswer"
        case answerLanguage = "answer_language"
        case answerLanguageCamel = "answerLanguage"
        case errors
        case natural
        case alternative
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        question = try container.decodeIfPresent(String.self, forKey: .question)
        userAnswer = try container.decodeIfPresent(String.self, forKey: .userAnswer)
            ?? container.decodeIfPresent(String.self, forKey: .userAnswerCamel)
            ?? ""
        answerLanguage = try container.decodeIfPresent(String.self, forKey: .answerLanguage)
            ?? container.decodeIfPresent(String.self, forKey: .answerLanguageCamel)
        errors = try container.decodeIfPresent([ErrorDTO].self, forKey: .errors)
        natural = try container.decodeIfPresent(String.self, forKey: .natural)
        alternative = try container.decodeIfPresent(String.self, forKey: .alternative)
    }
}

private struct ErrorDTO: Decodable {
    var excerpt: String?
    var kind: String?
    var problem: String?
    var fix: String?
}
