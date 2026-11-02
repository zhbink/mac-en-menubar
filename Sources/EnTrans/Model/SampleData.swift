import AppKit
import Foundation

enum SampleData {
    static let englishJSON = """
    {
      "answers": [
        {
          "question": "What did you do yesterday?",
          "user_answer": "I go to park yesterday.",
          "answer_language": "en",
          "errors": [
            {
              "excerpt": "go",
              "kind": "tense",
              "problem": "说昨天的事要用过去式",
              "fix": "went"
            },
            {
              "excerpt": "park",
              "kind": "article",
              "problem": "单数可数名词前面要有冠词",
              "fix": "the park"
            }
          ],
          "natural": "I went to the park yesterday.",
          "alternative": ""
        }
      ],
      "summary": "主要是过去式和冠词。"
    }
    """

    static let chineseJSON = """
    {
      "answers": [
        {
          "question": "Describe your weekend.",
          "user_answer": "我周末一般在家看书，有时候会出门散步。",
          "answer_language": "zh",
          "errors": [],
          "natural": "I usually stay home and read on weekends, and sometimes I go out for a walk.",
          "alternative": "On weekends I mostly read at home, though I'll go for a walk now and then."
        }
      ],
      "summary": "这是中文回答，已换成地道英文。"
    }
    """

    static func makeSessions(store: ReviewStore) -> [ReviewSession] {
        let specs: [(String, String, String)] = [
            (englishJSON, "示例 · 英文回答", "What did you do yesterday?\nI go to park yesterday."),
            (chineseJSON, "示例 · 中文回答", "Describe your weekend.\n我周末一般在家看书，有时候会出门散步。"),
        ]
        return specs.compactMap { json, title, picture in
            guard let payload = try? ReviewParser.parse(json) else { return nil }
            let id = UUID()
            let filename = (try? store.saveImage(previewJPEG(title: title, body: picture), id: id)) ?? ""
            return ReviewSession(
                id: id,
                createdAt: Date(),
                imageFilename: filename,
                rawJSON: json,
                payload: payload,
                oversized: false
            )
        }
    }

    private static func previewJPEG(title: String, body: String) -> Data {
        let size = NSSize(width: 720, height: 360)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.91, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.16, alpha: 1),
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor(calibratedWhite: 0.28, alpha: 1),
        ]
        title.draw(in: NSRect(x: 28, y: 280, width: 660, height: 40), withAttributes: titleAttrs)
        body.draw(in: NSRect(x: 28, y: 40, width: 660, height: 220), withAttributes: bodyAttrs)
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        else {
            return Data()
        }
        return jpeg
    }
}
