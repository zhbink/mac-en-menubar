import Foundation

struct ErrorRow: Identifiable, Equatable {
    var id: UUID
    var sessionID: UUID
    var answerID: UUID
    var createdAt: Date
    var question: String
    var userAnswer: String
    var excerpt: String
    var kind: String
    var problem: String
    var fix: String
    var natural: String
    var mastered: Bool
}

struct ChineseRow: Identifiable, Equatable {
    var id: UUID
    var sessionID: UUID
    var createdAt: Date
    var question: String
    var chinese: String
    var natural: String
    var alternative: String
    var mastered: Bool
}

struct KindCount: Identifiable, Equatable {
    var kind: String
    var count: Int
    var id: String { kind }
}

enum SummaryBuilder {
    static func errorRows(
        sessions: [ReviewSession],
        includeMastered: Bool,
        kind: String?,
        query: String
    ) -> [ErrorRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return sessions
            .flatMap { session in
                session.payload.answers.flatMap { answer in
                    guard answer.answerLanguage != .zh else { return [ErrorRow]() }
                    return answer.errors.map { error in
                        ErrorRow(
                            id: error.id,
                            sessionID: session.id,
                            answerID: answer.id,
                            createdAt: session.createdAt,
                            question: answer.question,
                            userAnswer: answer.userAnswer,
                            excerpt: error.excerpt,
                            kind: error.kind,
                            problem: error.problem,
                            fix: error.fix,
                            natural: answer.natural,
                            mastered: error.mastered
                        )
                    }
                }
            }
            .filter { includeMastered || !$0.mastered }
            .filter { kind == nil || kind == "all" || $0.kind == kind }
            .filter { row in
                guard !needle.isEmpty else { return true }
                return [
                    row.question, row.userAnswer, row.excerpt, row.problem, row.fix, row.natural,
                ].joined(separator: "\n").lowercased().contains(needle)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func chineseRows(
        sessions: [ReviewSession],
        includeMastered: Bool,
        query: String
    ) -> [ChineseRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return sessions
            .flatMap { session in
                session.payload.answers.compactMap { answer -> ChineseRow? in
                    guard answer.answerLanguage == .zh else { return nil }
                    return ChineseRow(
                        id: answer.id,
                        sessionID: session.id,
                        createdAt: session.createdAt,
                        question: answer.question,
                        chinese: answer.userAnswer,
                        natural: answer.natural,
                        alternative: answer.alternative,
                        mastered: answer.mastered
                    )
                }
            }
            .filter { includeMastered || !$0.mastered }
            .filter { row in
                guard !needle.isEmpty else { return true }
                return [row.question, row.chinese, row.natural, row.alternative]
                    .joined(separator: "\n")
                    .lowercased()
                    .contains(needle)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func kindCounts(sessions: [ReviewSession], includeMastered: Bool) -> [KindCount] {
        let rows = errorRows(sessions: sessions, includeMastered: includeMastered, kind: nil, query: "")
        let grouped = Dictionary(grouping: rows, by: \.kind)
        return grouped
            .map { KindCount(kind: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.kind < rhs.kind }
                return lhs.count > rhs.count
            }
    }
}

enum MarkdownExport {
    static func make(errors: [ErrorRow], chinese: [ChineseRow]) -> String {
        var lines: [String] = ["# Gloss 纠正本", ""]
        lines.append("## 英文错误")
        lines.append("")
        if errors.isEmpty {
            lines.append("没有未掌握的英文错误。")
            lines.append("")
        } else {
            for row in errors {
                lines.append("### \(ErrorKind.label(row.kind))")
                lines.append("")
                if !row.question.isEmpty { lines.append("- 题目：\(row.question)") }
                lines.append("- 原句：\(row.userAnswer)")
                if !row.excerpt.isEmpty { lines.append("- 问题片段：\(row.excerpt)") }
                if !row.problem.isEmpty { lines.append("- 说明：\(row.problem)") }
                if !row.fix.isEmpty { lines.append("- 改法：\(row.fix)") }
                if !row.natural.isEmpty { lines.append("- 地道整句：\(row.natural)") }
                lines.append("")
            }
        }
        lines.append("## 中文对照")
        lines.append("")
        if chinese.isEmpty {
            lines.append("没有未掌握的中文回答。")
            lines.append("")
        } else {
            for row in chinese {
                if !row.question.isEmpty { lines.append("- 题目：\(row.question)") }
                lines.append("- 中文：\(row.chinese)")
                if !row.natural.isEmpty { lines.append("- 推荐英文：\(row.natural)") }
                if !row.alternative.isEmpty { lines.append("- 另一种说法：\(row.alternative)") }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }
}

enum DigestSource {
    static func make(errors: [ErrorRow], chinese: [ChineseRow]) -> String {
        var lines: [String] = ["请根据下面还没掌握的内容输出 json。", "", "英文错误："]
        if errors.isEmpty {
            lines.append("（无）")
        }
        for (index, row) in errors.enumerated() {
            lines.append("\(index + 1). 原句：\(row.userAnswer)")
            lines.append("   片段：\(row.excerpt) 类型：\(row.kind) 说明：\(row.problem) 改法：\(row.fix)")
            lines.append("   地道：\(row.natural)")
        }
        lines.append("")
        lines.append("中文回答：")
        if chinese.isEmpty {
            lines.append("（无）")
        }
        for (index, row) in chinese.enumerated() {
            lines.append("\(index + 1). 中文：\(row.chinese)")
            lines.append("   英文：\(row.natural)")
            if !row.alternative.isEmpty {
                lines.append("   另一种：\(row.alternative)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
