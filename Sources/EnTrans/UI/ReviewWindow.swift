import AppKit
import SwiftUI

struct ReviewWindow: View {
    @EnvironmentObject private var model: AppModel
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("纠正本")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Picker("页面", selection: $tab) {
                    Text("记录").tag(0)
                    Text("汇总").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().overlay(Palette.line)

            if tab == 0 {
                sessionBrowser
            } else {
                SummaryScreen()
            }
        }
        .background(Palette.paper)
    }

    private var sessionBrowser: some View {
        HStack(spacing: 0) {
            List(selection: $model.selectedSessionID) {
                ForEach(model.sessions) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                        Text(session.payload.summary.isEmpty ? "一次纠正" : session.payload.summary)
                            .font(.callout)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                    .tag(session.id)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 280)
            .scrollContentBackground(.hidden)

            Divider().overlay(Palette.line)

            if let session = model.sessions.first(where: { $0.id == model.selectedSessionID }) {
                SessionDetail(session: session)
            } else {
                VStack(spacing: 8) {
                    Text("还没有记录")
                        .font(.title3)
                        .foregroundStyle(Palette.ink)
                    Text("按 \(model.hotkey.display) 截一张，或载入示例看看。")
                        .foregroundStyle(Palette.muted)
                    Button("载入示例") { model.loadSamples() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct SessionDetail: View {
    @EnvironmentObject private var model: AppModel
    var session: ReviewSession
    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                    Spacer()
                    Button(confirmingDelete ? "确认删除" : "删除这条") {
                        if confirmingDelete {
                            model.deleteSession(session.id)
                        } else {
                            confirmingDelete = true
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Palette.error)
                }

                screenshot

                if !session.payload.summary.isEmpty {
                    Text(session.payload.summary)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                }

                ForEach(session.payload.answers) { answer in
                    AnswerCard(sessionID: session.id, answer: answer)
                }

                FollowUpSection(sessionID: session.id)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.paper)
    }

    @ViewBuilder
    private var screenshot: some View {
        let url = model.store.imageURL(filename: session.imageFilename)
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Palette.line, lineWidth: 1)
                )
        }
    }
}
