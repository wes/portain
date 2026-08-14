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
                    .fill(tint.opacity(0.12))
                    .frame(width: 50, height: 50)
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                    }
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

/// A monospaced port chip. Live ports read a touch brighter than dormant ones;
/// the row's status dot already carries the colour, so the chip stays neutral.
struct PortChip: View {
    let text: String
    var highlighted: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(highlighted ? Color.primary.opacity(0.75) : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Color.primary.opacity(highlighted ? 0.09 : 0.05),
                in: RoundedRectangle(cornerRadius: 5)
            )
    }
}

/// A muted "glass" button: near-colorless at rest, taking on its accent only
/// under the pointer. Used everywhere an action needs to be available without
/// shouting — colour is reserved for the moment you're about to act.
struct GlassButtonStyle: ButtonStyle {
    /// The colour the button adopts on hover / press.
    var accent: Color = .primary
    var hovering: Bool = false
    var cornerRadius: CGFloat = 8

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let active = isEnabled && (hovering || configuration.isPressed)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return configuration.label
            .foregroundStyle(active ? accent : Color.secondary)
            .background {
                shape.fill(active
                           ? accent.opacity(configuration.isPressed ? 0.26 : 0.16)
                           : Color.primary.opacity(0.06))
            }
            .overlay {
                shape.strokeBorder(active ? accent.opacity(0.4) : Color.primary.opacity(0.09),
                                   lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.12), value: active)
    }
}

/// Compact icon-only glass button for list rows and folder headers — the
/// small sibling of `DetailActionButton`, with its own hover tracking so it
/// only lights up when the pointer is on the button itself.
struct GlassIconButton: View {
    let systemImage: String
    var accent: Color = .primary
    var width: CGFloat = 22
    var height: CGFloat = 19
    var fontSize: CGFloat = 10
    var help: String?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: fontSize, weight: .semibold))
                .frame(width: width, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(GlassButtonStyle(accent: accent, hovering: hovering, cornerRadius: 6))
        .onHover { hovering = $0 }
        .help(help ?? "")
    }
}

/// Icon-only action button for detail-pane action bars, shared by the
/// container and port inspectors so both read consistently. Every button sits
/// quiet and grey until hovered; `prominent` actions then light up in their
/// own colour (stop red, start green, kill orange), while neutral utility
/// actions (Logs, Restart, Copy) merely brighten.
struct DetailActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .secondary
    var prominent: Bool = true
    let action: () -> Void

    @State private var hovering = false

    /// Neutral actions have no colour of their own — they just get brighter.
    private var accent: Color { prominent ? tint : .primary }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 24, height: 26)
                .contentShape(Rectangle())
                .accessibilityLabel(title)
        }
        .buttonStyle(GlassButtonStyle(accent: accent, hovering: hovering))
        .onHover { hovering = $0 }
        .help(title)
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
