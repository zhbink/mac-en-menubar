import Foundation

public struct CheckResult: Sendable {
    public var count: Int
    public var failures: [String]
}

public enum EnTransChecks {
    public static func run() -> CheckResult {
        var check = Check()
        check.exercise()
        return CheckResult(count: check.count, failures: check.failures)
    }
}

private struct Check {
    var failures: [String] = []
    var count = 0

    mutating func expect(_ condition: Bool, _ name: String) {
        count += 1
        if !condition { failures.append(name) }
    }

    mutating func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
        count += 1
        if actual != expected { failures.append("\(name): \(actual) != \(expected)") }
    }

    mutating func expectThrows(_ name: String, _ body: () throws -> Void) {
        count += 1
        do {
            try body()
            failures.append("\(name) did not throw")
        } catch {}
    }

    mutating func exercise() {
        let parsed = try! ReviewParser.parse(Fixtures.english)
        expectEqual(parsed.summary, "主要是过去式和冠词。", "summary")
        expectEqual(parsed.answers.count, 1, "answer count")
        let answer = parsed.answers[0]
        expectEqual(answer.answerLanguage, .en, "language")
        expectEqual(answer.userAnswer, "I go to park yesterday.", "user answer")
        expectEqual(answer.natural, "I went to the park yesterday.", "natural")
        expectEqual(answer.errors.map(\.kind), ["tense", "article"], "kinds")
        expectEqual(answer.errors.map(\.fix), ["went", "the park"], "fixes")
        expect(answer.errors.allSatisfy { !$0.mastered }, "not mastered")

        let fenced = try! ReviewParser.parse("```json\n\(Fixtures.english)\n```")
        expectEqual(fenced.answers.count, 1, "fenced")

        let prose = try! ReviewParser.parse("好的，下面是 json\n\(Fixtures.english)\n希望有帮助")
        expectEqual(prose.answers.first?.userAnswer, "I go to park yesterday.", "prose")

        let empty = try! ReviewParser.parse(#"{"answers":[],"summary":"没找到回答"}"#)
        expect(empty.answers.isEmpty, "empty answers")
        expectEqual(empty.summary, "没找到回答", "empty summary")

        let unknown = try! ReviewParser.parse("""
        {"answers":[{"user_answer":"He go home.","answer_language":"en","errors":[{"excerpt":"go","kind":"Foobar","problem":"动词","fix":"goes"}],"natural":"He goes home."}]}
        """)
        expectEqual(unknown.answers.first?.errors.first?.kind, "other", "unknown kind")
        expectEqual(unknown.summary, "", "missing summary")

        let zh = try! ReviewParser.parse(Fixtures.chinese)
        expectEqual(zh.answers[0].answerLanguage, .zh, "zh language")
        expect(zh.answers[0].errors.isEmpty, "zh drops errors")
        expectEqual(zh.answers[0].natural, "I usually read at home on weekends.", "zh natural")
        expectEqual(zh.answers[0].alternative, "On weekends I mostly stay in and read.", "zh alternative")

        let inferred = try! ReviewParser.parse(#"{"answers":[{"user_answer":"我想喝一杯咖啡","natural":"I'd like a cup of coffee.","errors":[{"kind":"grammar","problem":"x","fix":"x"}]}]}"#)
        expectEqual(inferred.answers[0].answerLanguage, .zh, "infer zh")
        expect(inferred.answers[0].errors.isEmpty, "infer drops errors")

        expectThrows("non json") { _ = try ReviewParser.parse("完全没有括号") }

        let sessions = [
            Fixtures.session(Fixtures.english, dayOffset: -1),
            Fixtures.session(Fixtures.chinese, dayOffset: 0),
            Fixtures.session(Fixtures.mixed, dayOffset: 0),
        ]
        let errors = SummaryBuilder.errorRows(sessions: sessions, includeMastered: false, kind: nil, query: "")
        expectEqual(errors.map(\.kind).sorted(), ["article", "mixed_language", "tense"], "error kinds")
        let chineseRows = SummaryBuilder.chineseRows(sessions: sessions, includeMastered: false, query: "")
        expectEqual(chineseRows.map(\.chinese), ["我周末一般在家看书。"], "chinese rows")
        let counts = SummaryBuilder.kindCounts(sessions: sessions, includeMastered: false)
        expectEqual(counts.map(\.kind).sorted(), ["article", "mixed_language", "tense"], "counts")
        expect(counts.allSatisfy { $0.count == 1 }, "each count is 1")

        var mastered = Fixtures.session(Fixtures.english, dayOffset: 0)
        mastered.payload.answers[0].errors[0].mastered = true
        let visible = SummaryBuilder.errorRows(sessions: [mastered], includeMastered: false, kind: nil, query: "")
        expectEqual(visible.map(\.kind), ["article"], "hide mastered")
        let tense = SummaryBuilder.errorRows(sessions: [mastered], includeMastered: true, kind: "tense", query: "")
        expectEqual(tense.count, 1, "tense filter")
        expect(tense[0].mastered, "tense mastered")
        let searched = SummaryBuilder.errorRows(sessions: [mastered], includeMastered: false, kind: nil, query: "the park")
        expectEqual(searched.count, 1, "search")

        var masteredChinese = Fixtures.session(Fixtures.chinese, dayOffset: 0)
        masteredChinese.payload.answers[0].mastered = true
        expect(SummaryBuilder.chineseRows(sessions: [masteredChinese], includeMastered: false, query: "").isEmpty, "hide mastered chinese")
        expectEqual(SummaryBuilder.chineseRows(sessions: [masteredChinese], includeMastered: true, query: "").count, 1, "show mastered chinese")

        let markdown = MarkdownExport.make(
            errors: SummaryBuilder.errorRows(
                sessions: [Fixtures.session(Fixtures.english, dayOffset: 0), Fixtures.session(Fixtures.chinese, dayOffset: 0)],
                includeMastered: false,
                kind: nil,
                query: ""
            ),
            chinese: SummaryBuilder.chineseRows(
                sessions: [Fixtures.session(Fixtures.english, dayOffset: 0), Fixtures.session(Fixtures.chinese, dayOffset: 0)],
                includeMastered: false,
                query: ""
            )
        )
        expect(markdown.contains("## 英文错误"), "markdown errors")
        expect(markdown.contains("I went to the park yesterday."), "markdown natural")
        expect(markdown.contains("## 中文对照"), "markdown chinese")
        expect(markdown.contains("I usually read at home on weekends."), "markdown translation")

        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("entrans-check-\(UUID().uuidString)")
        let store = ReviewStore(root: root)
        try! store.saveSessions([Fixtures.session(Fixtures.english, dayOffset: 0)])
        let loaded = store.loadSessions()
        expectEqual(loaded.count, 1, "store roundtrip count")
        expectEqual(loaded.first?.payload.answers.first?.userAnswer, "I go to park yesterday.", "store roundtrip text")
        expect(loaded.first?.followUps.isEmpty == true, "store roundtrip follow-ups")

        var withChat = Fixtures.session(Fixtures.english, dayOffset: 0)
        withChat.followUps = [FollowUpTurn(id: UUID(), role: "user", text: "the 是必须的吗？")]
        try! store.saveSessions([withChat])
        expectEqual(store.loadSessions().first?.followUps.first?.text, "the 是必须的吗？", "store follow-up text")
        try? FileManager.default.removeItem(at: root)

        expectEqual(NaturalCopy.text(from: parsed), "I went to the park yesterday.", "copy one natural")
        var both = parsed
        both.answers.append(
            Answer(
                id: UUID(),
                question: "",
                userAnswer: "x",
                answerLanguage: .zh,
                errors: [],
                natural: "  Second sentence.  ",
                alternative: "",
                mastered: false
            )
        )
        expectEqual(NaturalCopy.text(from: both), "I went to the park yesterday.\nSecond sentence.", "copy two naturals")
        var blank = parsed
        blank.answers[0].natural = "  "
        expectEqual(NaturalCopy.text(from: blank), "", "skip blank natural")

        let context = FollowUpContext.make(Fixtures.session(Fixtures.english, dayOffset: 0))
        expect(context.contains("I went to the park yesterday."), "follow-up keeps natural")
        expect(context.contains("the park"), "follow-up keeps fix")

        let legacyJSON = """
        {"id":"00000000-0000-0000-0000-000000000001","createdAt":"2026-11-02T07:29:00Z","imageFilename":"a.jpg","rawJSON":"{}","payload":{"answers":[],"summary":"旧记录"},"oversized":false}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacy = try! decoder.decode(ReviewSession.self, from: Data(legacyJSON.utf8))
        expect(legacy.followUps.isEmpty, "legacy session has no follow-ups")
        expectEqual(legacy.payload.summary, "旧记录", "legacy summary")
    }
}

private enum Fixtures {
    static let english = """
    {
      "answers": [
        {
          "question": "What did you do yesterday?",
          "user_answer": "I go to park yesterday.",
          "answer_language": "en",
          "errors": [
            {"excerpt": "go", "kind": "tense", "problem": "说昨天的事要用过去式", "fix": "went"},
            {"excerpt": "park", "kind": "article", "problem": "单数可数名词前面要有冠词", "fix": "the park"}
          ],
          "natural": "I went to the park yesterday.",
          "alternative": ""
        }
      ],
      "summary": "主要是过去式和冠词。"
    }
    """

    static let chinese = """
    {
      "answers": [{
        "question": "Describe your weekend.",
        "user_answer": "我周末一般在家看书。",
        "answer_language": "zh",
        "errors": [{"excerpt": "x", "kind": "grammar", "problem": "不该留下", "fix": "x"}],
        "natural": "I usually read at home on weekends.",
        "alternative": "On weekends I mostly stay in and read."
      }],
      "summary": "中文"
    }
    """

    static let mixed = """
    {
      "answers": [{
        "user_answer": "I usually 在家 read.",
        "answer_language": "mixed",
        "errors": [{"excerpt": "在家", "kind": "mixed_language", "problem": "这里夹了中文", "fix": "at home"}],
        "natural": "I usually read at home."
      }],
      "summary": "夹杂"
    }
    """

    static func session(_ json: String, dayOffset: TimeInterval) -> ReviewSession {
        let payload = try! ReviewParser.parse(json)
        return ReviewSession(
            id: UUID(),
            createdAt: Date().addingTimeInterval(dayOffset * 86_400),
            imageFilename: "",
            rawJSON: json,
            payload: payload,
            oversized: false
        )
    }
}
