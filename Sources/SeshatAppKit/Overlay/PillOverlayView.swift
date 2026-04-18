import SwiftUI

@MainActor
public struct PillOverlayView: View {
    @ObservedObject private var model: PillOverlayViewModel
    @State private var isRecordingPulseActive = false

    public init(model: PillOverlayViewModel) {
        _model = ObservedObject(wrappedValue: model)
    }

    public var body: some View {
        Group {
            switch model.visibility {
            case .hidden:
                EmptyView()
            case .recording:
                recordingPill
            case .transcribing:
                transcribingPill
            }
        }
        .allowsHitTesting(false)
    }

    private var recordingPill: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: 8, height: 8)
                .scaleEffect(isRecordingPulseActive ? 1.25 : 0.85)
                .opacity(isRecordingPulseActive ? 0.65 : 1)

            Text("Recording")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            Image(systemName: "stop.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 20, height: 20)
                .background(Color.white.opacity(0.18), in: Circle())
        }
        .padding(.horizontal, 14)
        .frame(width: 160, height: 40)
        .background(
            Capsule()
                .fill(Color(red: 0.80, green: 0.19, blue: 0.17))
        )
        .shadow(color: Color.black.opacity(0.18), radius: 12, y: 6)
        .onAppear {
            isRecordingPulseActive = false
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                isRecordingPulseActive = true
            }
        }
        .onDisappear {
            isRecordingPulseActive = false
        }
    }

    private var transcribingPill: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(.white)

            Text("Transcribing…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(width: 160, height: 40)
        .background(
            Capsule()
                .fill(Color(red: 0.23, green: 0.27, blue: 0.33))
        )
        .shadow(color: Color.black.opacity(0.16), radius: 12, y: 6)
    }
}
