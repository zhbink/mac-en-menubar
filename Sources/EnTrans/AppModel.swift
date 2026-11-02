import AppKit
import Combine
import Foundation

public enum WorkPhase: Equatable {
    case idle
    case capturing
    case analyzing
    case digesting
    case followingUp
}

@MainActor
public final class AppModel: ObservableObject {
    @Published public var phase: WorkPhase = .idle
    @Published var sessions: [ReviewSession] = []
    @Published var digest: StudyDigest?
    @Published var banner: String?
    @Published var notice: String?
    @Published var followUpSessionID: UUID?
    @Published var captureMode: CaptureMode
    @Published var modelName: String
    @Published var hotkey: HotkeySpec
    @Published var hasAPIKey = false
    @Published var apiKeyHint = ""
    @Published var selectedSessionID: UUID?

    let store: ReviewStore
    private let presenter = WindowPresenter()
    private let globalHotkey = GlobalHotkey()
    private let statusBar = StatusBarController()

    public init() {
        let root = Self.storeRoot()
        let store = ReviewStore(root: root)
        try? store.prepare()
        self.store = store
        let loaded = store.loadSessions()
        self.sessions = loaded
        self.digest = store.loadDigest()
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: DefaultsKey.mode), let mode = CaptureMode(rawValue: raw) {
            captureMode = mode
        } else {
            captureMode = .region
        }
        let storedModel = defaults.string(forKey: DefaultsKey.model)?.trimmingCharacters(in: .whitespacesAndNewlines)
        modelName = (storedModel?.isEmpty == false ? storedModel! : "deepseek-flash")
        if defaults.object(forKey: DefaultsKey.keyCode) != nil {
            hotkey = HotkeySpec(
                keyCode: UInt32(defaults.integer(forKey: DefaultsKey.keyCode)),
                carbonModifiers: UInt32(defaults.integer(forKey: DefaultsKey.mods)),
                keyLabel: defaults.string(forKey: DefaultsKey.label) ?? "E"
            )
        } else {
            hotkey = .defaultSpec
        }
        selectedSessionID = loaded.first?.id
        refreshKey()
        presenter.attach(self)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statusBar.install(model: self)
        }
        HotkeyBridge.onFire = { [weak self] in
            self?.startCapture()
        }
        if !globalHotkey.register(hotkey) {
            banner = "默认快捷键没注册上，可以在设置里换一个。"
        }
        if sessions.isEmpty,
           FileManager.default.fileExists(atPath: store.root.appendingPathComponent("reviews.json.bad").path) {
            banner = "原来的纠正本读不了，已改名为 reviews.json.bad。"
        }
        schedulePreviewIfNeeded()
    }

    public var isBusy: Bool { phase != .idle }

    func startCapture() {
        guard phase == .idle else { return }
        guard hasAPIKey else {
            banner = DeepSeekError.missingKey.localizedDescription
            statusBar.close()
            presenter.show(.settings)
            return
        }
        if !Screenshot.hasPermission() {
            Screenshot.requestPermission()
            banner = ScreenshotError.permission.localizedDescription
            statusBar.close()
            presenter.show(.settings)
            return
        }
        let mode = captureMode
        let key = KeychainStore.read() ?? ""
        let model = modelName
        statusBar.close()
        phase = .capturing
        banner = nil
        notice = nil
        Task {
            do {
                try? await Task.sleep(for: .milliseconds(80))
                guard let shot = try await Screenshot.capture(mode: mode) else {
                    phase = .idle
                    return
                }
                phase = .analyzing
                let client = DeepSeekClient(apiKey: key, model: model)
                let analyzed = try await client.analyze(imageJPEG: shot.jpeg)
                let id = UUID()
                let filename = try store.saveImage(shot.jpeg, id: id)
                let session = ReviewSession(
                    id: id,
                    createdAt: Date(),
                    imageFilename: filename,
                    rawJSON: analyzed.raw,
                    payload: analyzed.payload,
                    oversized: shot.oversized
                )
                sessions.insert(session, at: 0)
                selectedSessionID = session.id
                try store.saveSessions(sessions)
                phase = .idle
                banner = nil
                copyNatural(analyzed.payload)
                statusBar.show()
            } catch {
                phase = .idle
                banner = error.localizedDescription
                statusBar.show()
            }
        }
    }

    func askFollowUp(sessionID: UUID, question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, phase == .idle else { return }
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard let key = KeychainStore.read() else {
            banner = DeepSeekError.missingKey.localizedDescription
            statusBar.close()
            presenter.show(.settings)
            return
        }
        let prior = sessions[index].followUps
        let correction = FollowUpContext.make(sessions[index])
        sessions[index].followUps.append(FollowUpTurn(id: UUID(), role: "user", text: question))
        persistSessions()
        phase = .followingUp
        followUpSessionID = sessionID
        banner = nil
        let modelName = modelName
        Task {
            do {
                let client = DeepSeekClient(apiKey: key, model: modelName)
                let reply = try await client.followUp(correction: correction, prior: prior, question: question)
                phase = .idle
                followUpSessionID = nil
                guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
                sessions[index].followUps.append(FollowUpTurn(id: UUID(), role: "assistant", text: reply))
                persistSessions()
            } catch {
                phase = .idle
                followUpSessionID = nil
                banner = error.localizedDescription
            }
        }
    }

    func openReview() {
        if selectedSessionID == nil {
            selectedSessionID = sessions.first?.id
        }
        statusBar.close()
        presenter.show(.review)
    }

    func openSettings() {
        statusBar.close()
        presenter.show(.settings)
    }

    func deleteSession(_ id: UUID) {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        sessions.removeAll { $0.id == id }
        store.deleteImage(filename: session.imageFilename)
        if selectedSessionID == id {
            selectedSessionID = sessions.first?.id
        }
        persistSessions()
    }

    func setErrorMastered(sessionID: UUID, errorID: UUID, mastered: Bool) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        var session = sessions[sessionIndex]
        for answerIndex in session.payload.answers.indices {
            guard let errorIndex = session.payload.answers[answerIndex].errors.firstIndex(where: { $0.id == errorID }) else {
                continue
            }
            session.payload.answers[answerIndex].errors[errorIndex].mastered = mastered
            sessions[sessionIndex] = session
            persistSessions()
            return
        }
    }

    func setAnswerMastered(sessionID: UUID, answerID: UUID, mastered: Bool) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        var session = sessions[sessionIndex]
        guard let answerIndex = session.payload.answers.firstIndex(where: { $0.id == answerID }) else { return }
        session.payload.answers[answerIndex].mastered = mastered
        sessions[sessionIndex] = session
        persistSessions()
    }

    func generateDigest() {
        guard phase == .idle else { return }
        guard let key = KeychainStore.read() else {
            banner = DeepSeekError.missingKey.localizedDescription
            presenter.show(.settings)
            return
        }
        let errors = Array(SummaryBuilder.errorRows(sessions: sessions, includeMastered: false, kind: nil, query: "").prefix(60))
        let chinese = Array(SummaryBuilder.chineseRows(sessions: sessions, includeMastered: false, query: "").prefix(40))
        guard !errors.isEmpty || !chinese.isEmpty else {
            banner = "没有未掌握的内容。先记几条，或把「我记住了」取消。"
            return
        }
        phase = .digesting
        banner = nil
        let prompt = DigestSource.make(errors: errors, chinese: chinese)
        let model = modelName
        Task {
            do {
                let client = DeepSeekClient(apiKey: key, model: model)
                let result = try await client.digest(prompt: prompt)
                digest = result
                try store.saveDigest(result)
                phase = .idle
            } catch {
                phase = .idle
                banner = error.localizedDescription
            }
        }
    }

    func loadSamples() {
        let made = SampleData.makeSessions(store: store)
        sessions.insert(contentsOf: made, at: 0)
        selectedSessionID = made.first?.id
        persistSessions()
        statusBar.close()
        presenter.show(.review)
    }

    func saveAPIKey(_ value: String) throws {
        try KeychainStore.write(value)
        refreshKey()
        if hasAPIKey, banner == DeepSeekError.missingKey.localizedDescription {
            banner = nil
        }
    }

    func clearAPIKey() throws {
        try KeychainStore.delete()
        refreshKey()
    }

    func updateModelName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modelName = trimmed
        UserDefaults.standard.set(trimmed, forKey: DefaultsKey.model)
    }

    func updateCaptureMode(_ mode: CaptureMode) {
        captureMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: DefaultsKey.mode)
    }

    func updateHotkey(_ spec: HotkeySpec) {
        let previous = hotkey
        if globalHotkey.register(spec) {
            hotkey = spec
            let defaults = UserDefaults.standard
            defaults.set(Int(spec.keyCode), forKey: DefaultsKey.keyCode)
            defaults.set(Int(spec.carbonModifiers), forKey: DefaultsKey.mods)
            defaults.set(spec.keyLabel, forKey: DefaultsKey.label)
            banner = nil
        } else {
            hotkey = previous
            _ = globalHotkey.register(previous)
            banner = "这个快捷键不可用，可能被其他应用占用了。"
        }
    }

    func revealScreenRecordingSettings() {
        Screenshot.openSettings()
    }

    private func copyNatural(_ payload: ReviewPayload) {
        let text = NaturalCopy.text(from: payload)
        guard !text.isEmpty else {
            notice = nil
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let count = payload.answers.filter { !$0.natural.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        notice = count > 1 ? "这几句地道英文已复制，可以直接粘贴。" : "地道英文已复制，可以直接粘贴。"
    }

    private func persistSessions() {
        do {
            try store.saveSessions(sessions)
        } catch {
            banner = "保存失败：\(error.localizedDescription)"
        }
    }

    private func refreshKey() {
        let secret = KeychainStore.read()
        hasAPIKey = secret != nil
        apiKeyHint = KeychainStore.hint(secret)
    }

    private func schedulePreviewIfNeeded() {
        let arguments = CommandLine.arguments
        if arguments.contains("--reveal-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.statusBar.show()
            }
        }
        if let flag = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(arguments.index(after: flag)) {
            let path = arguments[arguments.index(after: flag)]
            try? FileManager.default.removeItem(at: store.root)
            try? store.prepare()
            sessions = []
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                self.loadSamples()
                self.writeSnapshots(to: URL(fileURLWithPath: path, isDirectory: true))
            }
            return
        }
        guard arguments.contains("--show-samples") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            if self.sessions.isEmpty {
                self.loadSamples()
            } else {
                self.openReview()
            }
        }
    }

    private static func storeRoot() -> URL {
        if CommandLine.arguments.contains("--show-samples") || CommandLine.arguments.contains("--snapshot") {
            return URL(fileURLWithPath: "/tmp/entrans-preview", isDirectory: true)
        }
        return ReviewStore.applicationSupport()
    }
}

private enum DefaultsKey {
    static let mode = "EnTrans.captureMode"
    static let model = "EnTrans.model"
    static let keyCode = "EnTrans.hotkey.keyCode"
    static let mods = "EnTrans.hotkey.modifiers"
    static let label = "EnTrans.hotkey.label"
}
