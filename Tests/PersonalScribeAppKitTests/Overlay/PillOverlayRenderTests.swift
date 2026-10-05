import AppKit
import SwiftUI
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

@MainActor
final class PillOverlayRenderTests: XCTestCase {
    func testRenderEveryRedesignedPillState() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["NINIMMA_PILL_RENDER_DIR"],
              !outputPath.isEmpty else {
            throw XCTSkip("Set NINIMMA_PILL_RENDER_DIR to render pill PNGs")
        }
        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let states: [(name: String, visibility: PillVisibilityState, hovered: Bool, modeCount: Int)] = [
            ("idle", .idle, false, 2),
            ("idle-hover", .idle, true, 2),
            ("idle-hover-single", .idle, true, 1),
            ("recording", .recording, false, 2),
            ("recording-hover", .recording, true, 2),
            ("paused", .paused(elapsedSeconds: 23), false, 2),
            ("transcribing", .transcribing, false, 2),
        ]
        let schemes: [(name: String, value: ColorScheme)] = [
            ("dark", .dark),
            ("light", .light),
        ]

        for style in [PillStyle.mini, .classic] {
            for scheme in schemes {
                for state in states {
                    let model = PillOverlayViewModel(
                        visibility: state.visibility,
                        visibilityMode: .alwaysOn
                    )
                    model.setPillStyle(style)
                    model.setHovered(state.hovered)
                    model.setAvailableModeCount(state.modeCount)
                    model.audioLevel = 0.55
                    model.waveformRenderDate = Date(timeIntervalSinceReferenceDate: 0)
                    model.waveformPaletteOverride = .champagne

                    let size = PillOverlayView.size(
                        for: state.visibility,
                        style: style,
                        isHovered: state.hovered
                    )
                    let rootView = PillOverlayView(model: model)
                        .environment(\.colorScheme, scheme.value)
                        .frame(width: size.width, height: size.height)
                    let hostingView = NSHostingView(rootView: rootView)
                    hostingView.frame = NSRect(origin: .zero, size: size)
                    hostingView.layoutSubtreeIfNeeded()

                    let png = try renderPNG(view: hostingView, size: size)
                    let name = "\(style.rawValue.lowercased())-\(scheme.name)-\(state.name).png"
                    try png.write(to: outputDirectory.appendingPathComponent(name))
                }
            }
        }
    }

    private func renderPNG(view: NSView, size: CGSize) throws -> Data {
        let scale = 2
        let representation = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width) * scale,
                pixelsHigh: Int(size.height) * scale,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        representation.size = size
        view.cacheDisplay(in: view.bounds, to: representation)
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    }
}
