import AppKit
import SwiftUI

private struct ResultHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public struct MenuBarLabel: View {
    var phase: WorkPhase

    public init(phase: WorkPhase) {
        self.phase = phase
    }

    public var body: some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
            if phase != .idle {
                Text("…")
            }
        }
    }

    private var symbol: String {
        switch phase {
        case .idle:
            return "character.book.closed"
        case .capturing:
            return "viewfinder"
        case .analyzing, .digesting, .followingUp:
            return "ellipsis.circle"
        }
    }
}

public struct MenuPanel: View {
    @EnvironmentObject private var model: AppModel

    public init() {}

    @State private var resultHeight: CGFloat = 0

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle()
                .fill(Palette.line)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                statusLine

                if let banner = model.banner {
                    BannerText(text: banner)
                }

                if let latest = model.sessions.first {
                    latestResult(latest)
                    FollowUpSection(sessionID: latest.id, showsComposer: false, scrolls: true, maxHeight: 168)
                    FollowUpComposer(sessionID: latest.id)
                } else {
                    Text("按 \(model.hotkey.display) 把题目和你的回答圈进去。英文会改错，中文会换成地道英文。")
                        .font(.callout)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    model.startCapture()
                } label: {
                    Text(captureTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isBusy)

                Button {
                    model.openReview()
                } label: {
                    Text("纠正本")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())

                HStack(spacing: 16) {
                    Button("设置") { model.openSettings() }
                    Button("载入示例") { model.loadSamples() }
                    Spacer()
                    Button("退出") { NSApp.terminate(nil) }
                }
                .buttonStyle(.borderless)
                .font(.callout)
                .foregroundStyle(Palette.muted)
            }
            .padding(16)
        }
        .frame(width: 420)
        .background(Palette.paper)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.good)
            Text("Gloss")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Spacer()
            Keycap(text: model.hotkey.display)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func latestResult(_ latest: ReviewSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel(text: "最近一次")
                    Spacer()
                    Text(latest.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
                if latest.oversized {
                    BannerText(text: "这张图比较大，小字可能认错。下次可以只框住题目和回答。", tone: .note)
                }
                if !latest.payload.summary.isEmpty {
                    Text(latest.payload.summary)
                        .font(.callout)
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let notice = model.notice {
                    BannerText(text: notice, tone: .note)
                }
                if latest.payload.answers.isEmpty {
                    Text("没有认出你的回答。把选区收紧到题目和回答后再试一次。")
                        .font(.callout)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(latest.payload.answers) { answer in
                        AnswerCard(sessionID: latest.id, answer: answer)
                    }
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ResultHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .frame(height: min(max(resultHeight, 1), 390))
        .onPreferenceChange(ResultHeightKey.self) { resultHeight = $0 }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .capturing:
            Label("正在等待框选", systemImage: "viewfinder")
                .font(.callout)
                .foregroundStyle(Palette.muted)
        case .analyzing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在看这张图")
                    .font(.callout)
                    .foregroundStyle(Palette.muted)
            }
        case .digesting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在整理复习")
                    .font(.callout)
                    .foregroundStyle(Palette.muted)
            }
        case .followingUp:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在回答")
                    .font(.callout)
                    .foregroundStyle(Palette.muted)
            }
        }
    }

    private var captureTitle: String {
        switch model.captureMode {
        case .region: return "截图纠正"
        case .fullScreen: return "截当前屏幕"
        }
    }
}
