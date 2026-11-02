import AppKit
import SwiftUI

enum Palette {
    static let paper = Color(red: 0.957, green: 0.933, blue: 0.888)
    static let card = Color(red: 0.996, green: 0.988, blue: 0.970)
    static let ink = Color(red: 0.145, green: 0.122, blue: 0.098)
    static let muted = Color(red: 0.40, green: 0.35, blue: 0.29)
    static let line = Color(red: 0.78, green: 0.72, blue: 0.62)
    static let error = Color(red: 0.60, green: 0.22, blue: 0.18)
    static let errorWash = Color(red: 0.60, green: 0.22, blue: 0.18).opacity(0.10)
    static let good = Color(red: 0.11, green: 0.36, blue: 0.34)
    static let goodWash = Color(red: 0.11, green: 0.36, blue: 0.34).opacity(0.14)
    static let nsPaper = NSColor(calibratedRed: 0.957, green: 0.933, blue: 0.888, alpha: 1)
}

struct BannerText: View {
    var text: String
    var tone: Tone = .error

    enum Tone { case error, note }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(tone == .error ? Palette.error : Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(tone == .error ? Palette.errorWash : Palette.goodWash)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SectionLabel: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.muted)
    }
}

struct Keycap: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Palette.line, lineWidth: 1)
            )
    }
}

struct InlineMarkdown: View {
    var text: String

    var body: some View {
        Text(rendered)
            .font(.callout)
            .foregroundStyle(Palette.ink)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var rendered: AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let parsed = try? AttributedString(markdown: text, options: options) {
            return parsed
        }
        return AttributedString(text)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.75))
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.good.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.35))
            )
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Palette.ink.opacity(isEnabled ? 1 : 0.4))
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.card.opacity(configuration.isPressed ? 0.65 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Palette.line, lineWidth: 1)
            )
    }
}

struct SendButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.good.opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.35))
            )
    }
}
