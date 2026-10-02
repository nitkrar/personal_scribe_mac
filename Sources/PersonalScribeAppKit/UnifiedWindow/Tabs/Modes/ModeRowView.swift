import SwiftUI
import PersonalScribeCore

/// Validity status of a single custom mode row (#089 L-8). Used by the
/// view-model + row to surface the warning chip.
public enum ModeRowValidity: Equatable, Sendable {
    case valid
    case invalid(reason: String)
}

/// Single mode row in the modes-list view (#089 L-11..L-13).
@MainActor
struct ModeRowView: View {
    let mode: WorkflowMode
    let isCurrent: Bool
    let isDefault: Bool
    let validity: ModeRowValidity
    let onTapBody: () -> Void
    let onTapStar: () -> Void

    var body: some View {
        // No gesture on the row itself: in a macOS `List`, row-level
        // buttons and tap gestures intercept `.onMove` and swipe input.
        // The list's selection and
        // primary action (double-click / Return) opens the mode; the
        // small chevron and star buttons own only their own frames.
        HStack(spacing: PersonalScribeTheme.Spacing.md) {
            Image(systemName: mode.glyph)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24, height: 24)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(mode.name)
                    .font(PersonalScribeTheme.Typography.body.font.weight(.medium))
                    .lineLimit(1)
                if case .invalid(let reason) = validity {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: PersonalScribeTheme.Spacing.sm)

            if isCurrent {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Current mode")
            }

            Button(action: onTapStar) {
                Image(systemName: isDefault ? "star.fill" : "star")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDefault ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(isDefault ? "Default mode" : "Set as default")
            .accessibilityLabel(isDefault ? "Default mode" : "Set as default")

            Button(action: onTapBody) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open mode")
            .accessibilityLabel("Open \(mode.name)")
        }
        .padding(.vertical, PersonalScribeTheme.Spacing.sm)
        .padding(.horizontal, PersonalScribeTheme.Spacing.md)
        .contentShape(Rectangle())
    }
}
