import SwiftUI

struct ResultView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("这次纠正")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.ink)

                if model.phase == .analyzing || model.phase == .capturing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(model.phase == .capturing ? "正在等待框选" : "正在看这张图")
                            .foregroundStyle(Palette.muted)
                    }
                }

                if let banner = model.banner {
                    BannerText(text: banner)
                }

                if let session = model.sessions.first {
                    if session.oversized {
                        BannerText(
                            text: "这张图比较大，小字可能认错。下次可以只框住题目和回答。",
                            tone: .note
                        )
                    }
                    if !session.payload.summary.isEmpty {
                        Text(session.payload.summary)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                            .textSelection(.enabled)
                    }
                    if let notice = model.notice {
                        BannerText(text: notice, tone: .note)
                    }
                    if session.payload.answers.isEmpty {
                        Text("没有认出你的回答。把选区收紧到题目和回答后再试一次。")
                            .font(.callout)
                            .foregroundStyle(Palette.muted)
                    }
                    ForEach(session.payload.answers) { answer in
                        AnswerCard(sessionID: session.id, answer: answer)
                    }
                    Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                    FollowUpSection(sessionID: session.id)
                }

                Button {
                    model.startCapture()
                } label: {
                    Text("再截一张")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isBusy)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.paper)
    }
}
