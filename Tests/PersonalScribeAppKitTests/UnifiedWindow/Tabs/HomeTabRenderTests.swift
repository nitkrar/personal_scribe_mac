import AppKit
import PersonalScribeCore
import SwiftUI
import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class HomeTabRenderTests: XCTestCase {
    func testRenderHomeTabStates() async throws {
        guard let outputPath = ProcessInfo.processInfo.environment["NINIMMA_HOME_RENDER_DIR"],
              !outputPath.isEmpty else {
            throw XCTSkip("Set NINIMMA_HOME_RENDER_DIR to render Home PNGs")
        }
        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let schemes: [(name: String, value: ColorScheme)] = [
            ("dark", .dark),
            ("light", .light),
        ]
        let scenarios: [Scenario] = [
            Scenario(name: "two-pending", checklist: .twoPending, hasHistory: true),
            Scenario(name: "one-pending", checklist: .onePending, hasHistory: true),
            Scenario(name: "card-gone-dismissed", checklist: .dismissed, hasHistory: true),
            Scenario(name: "empty-history", checklist: .twoPending, hasHistory: false),
        ]

        for scheme in schemes {
            for scenario in scenarios {
                let rootView = try await makeHomeTab(scenario: scenario)
                    .environment(\.colorScheme, scheme.value)
                    .windowTint(.warm)
                    .padding(32)
                    .frame(width: 1_000, height: 760, alignment: .topLeading)
                    .background(
                        PersonalScribeTheme.Palette.for(scheme: scheme.value).appBackground
                    )
                let hostingView = NSHostingView(rootView: rootView)
                let size = CGSize(width: 1_000, height: 760)
                hostingView.frame = NSRect(origin: .zero, size: size)
                hostingView.layoutSubtreeIfNeeded()

                let png = try renderPNG(view: hostingView, size: size)
                try png.write(
                    to: outputDirectory.appendingPathComponent(
                        "home-\(scheme.name)-\(scenario.name).png"
                    )
                )
            }
        }
    }

    private func makeHomeTab(scenario: Scenario) async throws -> HomeTab {
        let referenceDate = Self.referenceDate
        let suite = "HomeTabRenderTests.\(scenario.name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        switch scenario.checklist {
        case .twoPending, .dismissed:
            break
        case .onePending:
            defaults.set(true, forKey: "HomeChecklistCustomizeShortcutComplete")
        }
        let checklist = HomeChecklistState(defaults: defaults)
        if scenario.checklist == .dismissed {
            checklist.dismiss()
        }

        let window = MetricsRange.allTime.window(
            anchoredAt: referenceDate,
            calendar: Self.calendar
        )
        let snapshot = MetricsSnapshot(
            rollups: scenario.hasHistory
                ? MetricsRollups(
                    recordings: 37,
                    words: 12_480,
                    minutesSaved: 222,
                    averageWPM: 128,
                    sampleCount: 37,
                    windowStart: window.start,
                    windowEnd: window.end
                )
                : .empty(window: window),
            recentTranscriptions: scenario.hasHistory ? Self.entries : [],
            lastUpdatedAt: referenceDate,
            lastRefreshReason: .initialLoad
        )
        let store = MetricsSnapshotStore(
            reader: RenderMetricsReader(snapshot: snapshot),
            calendar: Self.calendar,
            referenceDateProvider: { referenceDate },
            defaults: defaults,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui)
        )
        await store.refresh(reason: .initialLoad)
        let viewModel = HomeTabViewModel(
            metrics: store,
            defaults: defaults,
            checklist: checklist
        )
        return HomeTab(viewModel: viewModel, referenceDate: referenceDate)
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

    private static let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static let entries = [
        TranscriptEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            timestamp: referenceDate.addingTimeInterval(-30),
            text: "Hello Ninimma, this is my first dictation.",
            audioDuration: 18,
            processingDuration: 0.4
        ),
        TranscriptEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            timestamp: referenceDate.addingTimeInterval(-12 * 60),
            text: "Can we move the design review to Thursday afternoon? I want Priya there.",
            audioDuration: 24,
            processingDuration: 0.5
        ),
        TranscriptEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            timestamp: referenceDate.addingTimeInterval(-60 * 60),
            text: "Note to self: benchmark the long-form transcription set.",
            audioDuration: 16,
            processingDuration: 0.3
        ),
    ]

    private struct Scenario {
        let name: String
        let checklist: ChecklistFixture
        let hasHistory: Bool
    }

    private enum ChecklistFixture: Equatable {
        case twoPending
        case onePending
        case dismissed
    }
}

private struct RenderMetricsReader: MetricsReading {
    let snapshot: MetricsSnapshot

    func loadSnapshot(window: MetricsWindow, recentLimit: Int) async throws -> MetricsSnapshot {
        snapshot
    }

    func recentTranscriptions(limit: Int) async throws -> [TranscriptEntry] {
        Array(snapshot.recentTranscriptions.prefix(limit))
    }
}
