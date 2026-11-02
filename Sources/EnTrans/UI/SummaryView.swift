import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SummaryScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var includeMastered = false
    @State private var kind = "all"
    @State private var page: Int

    init(initialPage: Int = 0) {
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        let errors = SummaryBuilder.errorRows(
            sessions: model.sessions,
            includeMastered: includeMastered,
            kind: kind,
            query: query
        )
        let chinese = SummaryBuilder.chineseRows(
            sessions: model.sessions,
            includeMastered: includeMastered,
            query: query
        )
        let counts = SummaryBuilder.kindCounts(sessions: model.sessions, includeMastered: includeMastered)

        VStack(spacing: 0) {
            controls
            Divider().overlay(Palette.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let banner = model.banner {
                        BannerText(text: banner)
                    }
                    if let digest = model.digest {
                        digestCard(digest)
                    }
                    Picker("汇总", selection: $page) {
                        Text("英文错误").tag(0)
                        Text("中文对照").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 280)

                    if page == 0 {
                        kindChips(counts)
                        if errors.isEmpty {
                            empty("没有要看的英文错误。")
                        } else {
                            ForEach(errors) { row in
                                errorRow(row)
                            }
                        }
                    } else if chinese.isEmpty {
                        empty("没有要看的中文回答。")
                    } else {
                        ForEach(chinese) { row in
                            chineseRow(row)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Palette.paper)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            TextField("搜索", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
            Toggle("包含已掌握", isOn: $includeMastered)
                .toggleStyle(.checkbox)
            Spacer()
            Button(model.phase == .digesting ? "正在生成" : "生成复习") {
                model.generateDigest()
            }
            .disabled(model.isBusy)
            Button("导出 Markdown") { export() }
                .disabled(model.isBusy)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func kindChips(_ counts: [KindCount]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "全部", value: "all", count: counts.reduce(0) { $0 + $1.count })
                ForEach(counts) { item in
                    chip(title: ErrorKind.label(item.kind), value: item.kind, count: item.count)
                }
            }
        }
    }

    private func chip(title: String, value: String, count: Int) -> some View {
        let selected = kind == value
        return Button {
            kind = value
        } label: {
            Text("\(title) \(count)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(selected ? Color.white : Palette.ink)
                .background(selected ? Palette.good : Palette.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Palette.line, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func errorRow(_ row: ErrorRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(ErrorKind.label(row.kind))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.error)
                Text(row.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                Spacer()
                Button(row.mastered ? "恢复" : "我记住了") {
                    model.setErrorMastered(sessionID: row.sessionID, errorID: row.id, mastered: !row.mastered)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.muted)
            }
            if !row.question.isEmpty {
                Text(row.question)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .textSelection(.enabled)
            }
            Text(row.userAnswer)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
            if !row.excerpt.isEmpty || !row.problem.isEmpty {
                Text([row.excerpt, row.problem].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
            }
            if !row.fix.isEmpty {
                Text("改成 \(row.fix)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.good)
                    .textSelection(.enabled)
            }
            if !row.natural.isEmpty {
                Text(row.natural)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.line, lineWidth: 1)
        )
        .opacity(row.mastered ? 0.5 : 1)
    }

    private func chineseRow(_ row: ChineseRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                Spacer()
                Button(row.mastered ? "恢复" : "我记住了") {
                    model.setAnswerMastered(sessionID: row.sessionID, answerID: row.id, mastered: !row.mastered)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.muted)
            }
            if !row.question.isEmpty {
                Text(row.question)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .textSelection(.enabled)
            }
            Text(row.chinese)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
            Text(row.natural)
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(Palette.good)
                .textSelection(.enabled)
            if !row.alternative.isEmpty {
                Text(row.alternative)
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.line, lineWidth: 1)
        )
        .opacity(row.mastered ? 0.5 : 1)
    }

    private func digestCard(_ digest: StudyDigest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "复习摘要 · \(digest.createdAt.formatted(date: .abbreviated, time: .shortened))")
            if !digest.patterns.isEmpty {
                Text("反复出现的问题")
                    .font(.callout.weight(.semibold))
                ForEach(digest.patterns, id: \.self) { item in
                    Text("· \(item)")
                        .textSelection(.enabled)
                }
            }
            ForEach(Array(digest.rewrites.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.source).foregroundStyle(Palette.muted).textSelection(.enabled)
                    Text(item.target).font(.system(.body, design: .serif)).textSelection(.enabled)
                    if !item.note.isEmpty {
                        Text(item.note).font(.caption).foregroundStyle(Palette.muted)
                    }
                }
            }
            ForEach(Array(digest.chineseToEnglish.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.chinese).textSelection(.enabled)
                    Text(item.english).font(.system(.body, design: .serif)).foregroundStyle(Palette.good).textSelection(.enabled)
                }
            }
            if !digest.drills.isEmpty {
                Text("挖空")
                    .font(.callout.weight(.semibold))
                ForEach(Array(digest.drills.enumerated()), id: \.offset) { index, item in
                    Text("\(index + 1). \(item)")
                        .font(.system(.body, design: .serif))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.goodWash)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
    }

    private func export() {
        let errors = SummaryBuilder.errorRows(
            sessions: model.sessions,
            includeMastered: includeMastered,
            kind: kind,
            query: query
        )
        let chinese = SummaryBuilder.chineseRows(
            sessions: model.sessions,
            includeMastered: includeMastered,
            query: query
        )
        let text = MarkdownExport.make(errors: errors, chinese: chinese)
        let panel = NSSavePanel()
        if let markdown = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [markdown]
        }
        panel.nameFieldStringValue = "Gloss-复习.md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            model.banner = "导出失败：\(error.localizedDescription)"
        }
    }
}
