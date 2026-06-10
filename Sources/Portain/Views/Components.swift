import SwiftUI

/// A clean, native hero header for detail panes: a tinted rounded-square icon
/// (or a short text glyph like a port number), a title, and a status subtitle.
struct DetailHeader: View {
    let symbol: String
    var symbolText: String? = nil
    let tint: Color
    let title: String
    var statusColor: Color? = nil
    let subtitle: String
    var busy: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 50, height: 50)
                if let symbolText {
                    Text(symbolText)
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(tint)
                        .minimumScaleFactor(0.5)
                        .padding(5)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 22))
                        .foregroundStyle(tint)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    if let statusColor {
                        Circle().fill(statusColor).frame(width: 7, height: 7)
                    }
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if busy { ProgressView().controlSize(.small) }
        }
        .padding(.vertical, 4)
    }
}

/// A small glowing status dot.
struct StatusDot: View {
    let color: Color
    var pulsing: Bool = false
    @State private var animate = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.35), lineWidth: animate && pulsing ? 6 : 0)
                    .scaleEffect(animate && pulsing ? 1.8 : 1)
            )
            .shadow(color: color.opacity(0.6), radius: 3)
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}

/// A pill-shaped colored label.
struct Pill: View {
    let text: String
    var color: Color = .secondary
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
            }
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
    }
}

/// A monospaced port chip.
struct PortChip: View {
    let text: String
    var highlighted: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(highlighted ? Color.accentColor : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                (highlighted ? Color.accentColor : Color.secondary).opacity(0.12),
                in: RoundedRectangle(cornerRadius: 5)
            )
    }
}

/// A circular toolbar-style action button used in detail panes.
struct ActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }
}

/// Labeled key/value row for detail inspectors.
struct InfoRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: monospaced ? .monospaced : .default))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Empty-state placeholder.
struct EmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.tertiary)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
