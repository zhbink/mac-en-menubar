import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var apiKey = ""
    @State private var modelDraft = ""
    @State private var recording = false
    @State private var monitor: Any?
    @State private var keyMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("设置")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.ink)

                if let banner = model.banner {
                    BannerText(text: banner)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "DeepSeek API Key")
                    Text(model.hasAPIKey ? "已保存在钥匙串 \(model.apiKeyHint)" : "还没填写")
                        .font(.callout)
                        .foregroundStyle(Palette.muted)
                    SecureField("sk-…", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("保存") { saveKey() }
                            .buttonStyle(.borderedProminent)
                            .tint(Palette.good)
                            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("清除") { clearKey() }
                            .disabled(!model.hasAPIKey)
                    }
                    if !keyMessage.isEmpty {
                        Text(keyMessage)
                            .font(.caption)
                            .foregroundStyle(Palette.good)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "模型")
                    TextField("deepseek-flash", text: $modelDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.updateModelName(modelDraft) }
                    Button("保存模型名") { model.updateModelName(modelDraft) }
                        .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "截图方式")
                    Picker("截图方式", selection: modeBinding) {
                        ForEach(CaptureMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    Text(captureHint)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "快捷键")
                    Text(model.hotkey.display)
                        .font(.title3.monospaced())
                        .foregroundStyle(Palette.ink)
                    Button(recording ? "请按快捷键，Esc 取消" : "设置快捷键") {
                        toggleRecording()
                    }
                    .buttonStyle(.bordered)
                    Text("需要至少一个修饰键，例如 ⌃⌥E。框选时按空格可以改成点选窗口。")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "屏幕录制")
                    Text(Screenshot.hasPermission() ? "系统已经允许 Gloss 录屏。" : "还没有录屏权限。第一次截图时系统会询问。")
                        .font(.callout)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("打开系统设置") { model.revealScreenRecordingSettings() }
                        .buttonStyle(.bordered)
                }

                Text("截图会发给 DeepSeek。API Key 在钥匙串里，纠正本只存在这台电脑上。")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.paper)
        .onAppear { modelDraft = model.modelName }
        .onDisappear { stopRecording() }
    }

    private var modeBinding: Binding<CaptureMode> {
        Binding(
            get: { model.captureMode },
            set: { model.updateCaptureMode($0) }
        )
    }

    private var captureHint: String {
        switch model.captureMode {
        case .region:
            return "按下快捷键后拖一块区域。模型会把大图缩小，框得越紧，字越清楚。"
        case .fullScreen:
            return "截鼠标所在的整块屏幕。画面太大时小字可能认错，练习时更适合框选。"
        }
    }

    private func saveKey() {
        do {
            try model.saveAPIKey(apiKey)
            apiKey = ""
            keyMessage = "已写入钥匙串。"
        } catch {
            keyMessage = ""
            model.banner = error.localizedDescription
        }
    }

    private func clearKey() {
        do {
            try model.clearAPIKey()
            keyMessage = "已清除。"
        } catch {
            model.banner = error.localizedDescription
        }
    }

    private func toggleRecording() {
        if recording {
            stopRecording()
        } else {
            recording = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 {
                    stopRecording()
                    return nil
                }
                if let spec = HotkeySpec.from(event: event) {
                    model.updateHotkey(spec)
                    stopRecording()
                }
                return nil
            }
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
