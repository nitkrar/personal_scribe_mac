import SwiftUI

private struct PulsingDot: View {
    let delay: Double
    let color: Color

    @State private var animate = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 4, height: 4)
            .opacity(animate ? 1.0 : 0.3)
            .scaleEffect(animate ? 1.2 : 0.8)
            .animation(
                .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: animate
            )
            .onAppear {
                animate = true
            }
    }
}

@MainActor
public struct PillOverlayView: View {
    @ObservedObject private var model: PillOverlayViewModel

    public init(model: PillOverlayViewModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    public var body: some View {
        ZStack {
            switch model.visibility {
            case .hidden:
                EmptyView()
            case .recording:
                recordingPill
                    .transition(pillTransition)
            case .transcribing:
                transcribingPill
                    .transition(pillTransition)
            }
        }
        .allowsHitTesting(false)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: model.visibility)
    }

    private var recordingPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.red)

            Text("Listening")
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)

            HStack(spacing: 4) {
                PulsingDot(delay: 0.0, color: .red)
                PulsingDot(delay: 0.2, color: .red)
                PulsingDot(delay: 0.4, color: .red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: 160, idealWidth: 180, minHeight: 40)
        .pillChrome
    }

    private var transcribingPill: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(.white)

            Text("Transcribing…")
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: 160, idealWidth: 180, minHeight: 40)
        .pillChrome
    }

    private var pillTransition: AnyTransition {
        .opacity
            .combined(with: .scale(scale: 0.92))
            .combined(with: .offset(y: 8))
    }
}

private extension View {
    var pillChrome: some View {
        self
            .background {
                Capsule()
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            }
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            }
    }
}
