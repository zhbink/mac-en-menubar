import AppKit
import SwiftUI

struct AnswerCard: View {
    @EnvironmentObject private var model: AppModel
    var sessionID: UUID
    var answer: Answer
    @State private var copiedTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !answer.question.isEmpty {
                prose(label: "题目", text: answer.question)
            }

            prose(
                label: "你的回答",
                text: answer.userAnswer.isEmpty ? "（没有认出文字）" : answer.userAnswer
            )

            if !answer.natural.isEmpty {
                recommendation
            }
            if answer.answerLanguage == .zh {
                if !answer.alternative.isEmpty {
                    englishBlock(title: "另一种说法", text: answer.alternative, emphasized: false)
                }
                masteredButton(
                    done: answer.mastered,
                    action: {
                        model.setAnswerMastered(sessionID: sessionID, answerID: answer.id, mastered: !answer.mastered)
                    }
                )
            } else if answer.errors.isEmpty {
                Text("这句没什么问题。")
                    .font(.callout)
                    .foregroundStyle(Palette.muted)
            } else {
                ForEach(answer.errors) { error in
                    errorBlock(error)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.line, lineWidth: 1)
        )
    }

    private func prose(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: label)
            Text(text)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var recommendation: some View {
        englishBlock(title: "地道英文", text: answer.natural, emphasized: true)
    }

    private func englishBlock(title: String, text: String, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: title)
                Spacer()
                Button(copiedTitle == title ? "已复制" : "复制") {
                    copy(title, text)
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.good)
            }
            Text(text)
                .font(.system(size: emphasized ? 18 : 16, weight: .regular, design: .serif))
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(emphasized ? Palette.goodWash : Palette.paper.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(emphasized ? Palette.good : Palette.line)
                .frame(width: 3)
                .padding(.vertical, 10)
        }
    }

    private func errorBlock(_ error: AnswerError) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(ErrorKind.label(error.kind))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.error)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Palette.errorWash)
                    .clipShape(Capsule())
                Spacer()
                Button(error.mastered ? "恢复" : "我记住了") {
                    model.setErrorMastered(sessionID: sessionID, errorID: error.id, mastered: !error.mastered)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.muted)
            }
            if !error.excerpt.isEmpty {
                Text(error.excerpt)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
            }
            if !error.problem.isEmpty {
                Text(error.problem)
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
            }
            if !error.fix.isEmpty {
                Text("改成 \(error.fix)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.good)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.errorWash)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .opacity(error.mastered ? 0.45 : 1)
    }

    private func masteredButton(done: Bool, action: @escaping () -> Void) -> some View {
        Button(done ? "恢复" : "我记住了", action: action)
            .buttonStyle(.borderless)
            .foregroundStyle(Palette.muted)
    }

    private func copy(_ title: String, _ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedTitle = title
    }
}
