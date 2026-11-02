import SwiftUI

struct FollowUpSection: View {
    @EnvironmentObject private var model: AppModel
    var sessionID: UUID
    var showsComposer: Bool = true
    var scrolls: Bool = true
    var maxHeight: CGFloat = 220

    private var session: ReviewSession? {
        model.sessions.first { $0.id == sessionID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "接着问这次")
            if let session, !session.followUps.isEmpty {
                thread(session.followUps)
            }
            if showsComposer {
                FollowUpComposer(sessionID: sessionID)
            }
        }
    }

    @ViewBuilder
    private func thread(_ turns: [FollowUpTurn]) -> some View {
        let column = VStack(alignment: .leading, spacing: 12) {
            ForEach(turns) { turn in
                bubble(turn)
                    .id(turn.id)
            }
        }
        if scrolls {
            ScrollViewReader { proxy in
                ScrollView { column }
                    .frame(maxHeight: maxHeight)
                    .onAppear {
                        guard let last = turns.last else { return }
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
            }
        } else {
            column
        }
    }

    private func bubble(_ turn: FollowUpTurn) -> some View {
        let isUser = turn.role == "user"
        return VStack(alignment: .leading, spacing: 4) {
            Text(isUser ? "我" : "Gloss")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isUser ? Palette.muted : Palette.good)
            if isUser {
                Text(turn.text)
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                InlineMarkdown(text: turn.text)
            }
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(isUser ? Palette.line : Palette.good)
                .frame(width: 2)
        }
    }
}

struct FollowUpComposer: View {
    @EnvironmentObject private var model: AppModel
    var sessionID: UUID
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.phase == .followingUp, model.followUpSessionID == sessionID {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在回答")
                        .font(.callout)
                        .foregroundStyle(Palette.muted)
                }
            }
            HStack(alignment: .center, spacing: 8) {
                TextField("例如：这里的 the 是必须加的吗？", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Palette.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Palette.line, lineWidth: 1)
                    )
                    .onSubmit(send)
                Button("发送", action: send)
                    .buttonStyle(SendButtonStyle())
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
            }
        }
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        model.askFollowUp(sessionID: sessionID, question: text)
    }
}
