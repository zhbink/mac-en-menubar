import AppKit
import CoreGraphics
import Foundation

enum CaptureMode: String, CaseIterable, Identifiable {
    case region
    case fullScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .region: return "框选区域"
        case .fullScreen: return "当前屏幕整屏"
        }
    }
}

struct PreparedShot {
    var jpeg: Data
    var oversized: Bool
}

enum ScreenshotError: LocalizedError, Sendable {
    case permission
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .permission:
            return "需要屏幕录制权限。请在系统设置里允许 Gloss，然后重试。"
        case .failed(let message):
            return message.isEmpty ? "截图失败。" : "截图失败：\(message)"
        }
    }
}

enum Screenshot {
    @MainActor
    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @MainActor
    static func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    @MainActor
    static func openSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
        ]
        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
    }

    /// Returns nil when the user cancels the selection.
    @MainActor
    static func capture(mode: CaptureMode) async throws -> PreparedShot? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("entrans-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }

        var arguments = ["-x", "-t", "jpg"]
        switch mode {
        case .region:
            arguments.append(contentsOf: ["-i", "-o"])
        case .fullScreen:
            arguments.append("-D\(displayIndexUnderMouse())")
        }
        arguments.append(url.path)

        let result = try await runScreencapture(arguments)
        let exists = FileManager.default.fileExists(atPath: url.path)
        if !exists {
            if result.code == 0 { return nil }
            let lowered = result.error.lowercased()
            if lowered.contains("permission") || lowered.contains("not permitted") || lowered.contains("screen") {
                throw ScreenshotError.permission
            }
            return nil
        }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return nil }
        return prepare(data)
    }

    static func prepare(_ data: Data) -> PreparedShot {
        guard let source = NSImage(data: data),
              let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return PreparedShot(jpeg: data, oversized: data.count > 1_500_000)
        }
        let width = cgImage.width
        let height = cgImage.height
        let longSide = max(width, height)
        let oversized = longSide > 2000 || width * height > 2_500_000
        let scale = min(1, 2048 / Double(max(longSide, 1)))
        if scale >= 0.999, data.count < 3_500_000, isJPEG(data) {
            return PreparedShot(jpeg: data, oversized: oversized)
        }
        let targetWidth = max(1, Int((Double(width) * scale).rounded()))
        let targetHeight = max(1, Int((Double(height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return PreparedShot(jpeg: data, oversized: oversized)
        }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let scaled = context.makeImage() else {
            return PreparedShot(jpeg: data, oversized: oversized)
        }
        let rep = NSBitmapImageRep(cgImage: scaled)
        var quality: CGFloat = 0.86
        var jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) ?? data
        while jpeg.count > 3_500_000, quality > 0.5 {
            quality -= 0.12
            jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) ?? jpeg
        }
        return PreparedShot(jpeg: jpeg, oversized: oversized)
    }

    static func displayIndexUnderMouse() -> Int {
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens
        if let index = screens.firstIndex(where: { $0.frame.contains(mouse) }) {
            return index + 1
        }
        return 1
    }

    private static func isJPEG(_ data: Data) -> Bool {
        data.count >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF
    }

    private static func runScreencapture(_ arguments: [String]) async throws -> (code: Int32, error: String) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = arguments
                let pipe = Pipe()
                process.standardError = pipe
                process.standardOutput = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: errorData, encoding: .utf8) ?? ""
                    continuation.resume(returning: (process.terminationStatus, message))
                } catch {
                    continuation.resume(throwing: ScreenshotError.failed(error.localizedDescription))
                }
            }
        }
    }
}
