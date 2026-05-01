import SwiftUI

@MainActor
struct StreamCardView: View {
    let text: String

    @AppStorage(StreamingCardOverflowModePreference.userDefaultsKey)
    private var overflowModeRawValue = StreamingCardOverflowMode.tailPinnedHeadEllipsis.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var overflowMode: StreamingCardOverflowMode {
        StreamingCardOverflowMode(rawValue: overflowModeRawValue) ?? .tailPinnedHeadEllipsis
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(PersonalScribeTheme.Pill.Dark.waveform.opacity(0.9))
                .frame(width: 7, height: 7)
                .shadow(
                    color: PersonalScribeTheme.Pill.Dark.waveform.opacity(0.35),
                    radius: 6
                )

            transcriptBody
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(PersonalScribeTheme.Pill.Dark.waveform)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 5)
    }

    private var background: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)
        return RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(palette.pillBackground.opacity(0.95))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                PersonalScribeTheme.Pill.Dark.waveform.opacity(0.3),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .background(
                VisualEffectBlur()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            )
    }

    @ViewBuilder
    private var transcriptBody: some View {
        switch overflowMode {
        case .tailPinnedHeadEllipsis:
            Text(text)
                .lineLimit(1)
                .truncationMode(.head)
        case .marquee:
            StreamCardMarqueeText(text: text)
        case .wordByWordFade:
            Text(text)
                .lineLimit(1)
                .truncationMode(.head)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.3), location: 0.08),
                            .init(color: .black, location: 0.2),
                            .init(color: .black, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }
}

@MainActor
private struct StreamCardMarqueeText: View {
    let text: String

    @State private var containerWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private let spacing: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                measuredText.hidden()

                if shouldMarquee {
                    HStack(spacing: spacing) {
                        plainText
                            .fixedSize(horizontal: true, vertical: false)
                        plainText
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .offset(x: offset)
                } else {
                    plainText
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .clipped()
            .onAppear {
                containerWidth = proxy.size.width
                restartAnimation()
            }
            .onChange(of: proxy.size.width) { _, newWidth in
                containerWidth = newWidth
                restartAnimation()
            }
            .onPreferenceChange(StreamCardTextWidthKey.self) { newWidth in
                textWidth = newWidth
                restartAnimation()
            }
        }
        .frame(height: 16)
    }

    private var shouldMarquee: Bool {
        textWidth > containerWidth && containerWidth > 0
    }

    private var plainText: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(PersonalScribeTheme.Pill.Dark.waveform)
    }

    private var measuredText: some View {
        plainText.background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: StreamCardTextWidthKey.self,
                    value: proxy.size.width
                )
            }
        )
    }

    private func restartAnimation() {
        offset = 0
        guard shouldMarquee else {
            return
        }

        DispatchQueue.main.async {
            offset = 0
            withAnimation(
                .linear(duration: max(6, Double(textWidth + spacing) / 32.0))
                    .repeatForever(autoreverses: false)
            ) {
                offset = -(textWidth + spacing)
            }
        }
    }
}

private struct StreamCardTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
