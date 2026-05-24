import Foundation
import PersonalScribeCore

/// Pure presenter for `ModelInfoPopover` — maps a `ModelDescriptor`
/// (ranked against its registered siblings) into header / rating /
/// size / detail sections. Split off the SwiftUI view so the
/// computed-relative ranking logic is XCTest-able.
///
/// Ticket #007. The ⓘ icon next to a model's display name in
/// `AIModelsTab` opens a popover backed by this presenter.
///
/// Ranking policy: ordinal-position within siblings that declare the
/// metric, mapped to 3 tiers. For N siblings at rank `r`, tier =
/// `(r * 3) / N` so the bar fills match consistently regardless of
/// registered-model count.
@MainActor
struct ModelInfoPopoverPresenter {
    let descriptor: ModelDescriptor
    /// All registered descriptors the current one is being compared
    /// against. Typically `BuiltInModelCatalog.registeredModels`.
    /// Current descriptor can be absent — the presenter inserts it
    /// defensively so rank computation never produces nonsense.
    let siblings: [ModelDescriptor]

    // MARK: - Header

    var title: String { descriptor.displayName }

    var subtitle: String { descriptor.shortDescription }

    // MARK: - Rating rows

    static let totalRatingSegments: Int = 3

    private static let speedLabels = ["Fastest", "Fast", "Slow"]
    private static let accuracyLabels = ["High", "Medium", "Low"]

    struct RatingRow: Equatable {
        let title: String
        let filledSegments: Int
        let totalSegments: Int
        let label: String
    }

    var speedRow: RatingRow? {
        guard descriptor.performance.rtfx != nil else { return nil }
        return ratingRow(
            title: "Speed",
            metric: { $0.rtfx },
            labels: Self.speedLabels,
            betterIsLower: false  // higher RTFx = faster
        )
    }

    var accuracyRow: RatingRow? {
        guard descriptor.performance.averageWER != nil else { return nil }
        return ratingRow(
            title: "Accuracy",
            metric: { $0.averageWER },
            labels: Self.accuracyLabels,
            betterIsLower: true  // lower WER = more accurate
        )
    }

    private func ratingRow(
        title: String,
        metric: (ModelPerformance) -> Double?,
        labels: [String],
        betterIsLower: Bool
    ) -> RatingRow? {
        let pool = candidatePool(metric: metric)
        guard !pool.isEmpty else { return nil }

        let sorted = pool.sorted { lhs, rhs in
            let a = metric(lhs.performance)!
            let b = metric(rhs.performance)!
            return betterIsLower ? a < b : a > b
        }
        guard let rank = sorted.firstIndex(where: { $0.id == descriptor.id }) else {
            return nil
        }

        // Tier 0 = top (best) → segments filled = totalRatingSegments
        // Tier 2 = bottom      → segments filled = 1
        let tier = (rank * Self.totalRatingSegments) / sorted.count
        let clampedTier = min(max(tier, 0), Self.totalRatingSegments - 1)
        let filled = Self.totalRatingSegments - clampedTier
        let label = labels[clampedTier]

        return RatingRow(
            title: title,
            filledSegments: filled,
            totalSegments: Self.totalRatingSegments,
            label: label
        )
    }

    /// Siblings that declare the metric, with `descriptor` inserted
    /// defensively if missing from the input list.
    private func candidatePool(
        metric: (ModelPerformance) -> Double?
    ) -> [ModelDescriptor] {
        var pool = siblings.filter { metric($0.performance) != nil }
        if !pool.contains(where: { $0.id == descriptor.id }) {
            if metric(descriptor.performance) != nil {
                pool.append(descriptor)
            }
        }
        return pool
    }

    // MARK: - Size

    var sizeValue: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: descriptor.approximateSizeBytes)
    }

    // MARK: - Detail rows

    struct InfoRow: Equatable {
        let title: String
        let value: String
        /// Render the value in a monospaced font — used for SHA-like
        /// values (revision) so columns align nicely.
        let monospaced: Bool
    }

    var detailRows: [InfoRow] {
        var rows: [InfoRow] = [
            InfoRow(
                title: "Architecture",
                value: descriptor.architecture,
                monospaced: false
            ),
            InfoRow(
                title: "Repository",
                value: descriptor.repository,
                monospaced: false
            ),
            InfoRow(
                title: "Revision",
                value: shortRevision,
                monospaced: true
            ),
        ]
        if let paramRow = parameterCountRow {
            rows.append(paramRow)
        }
        return rows
    }

    /// Revision truncated to the first 8 chars — compact commit
    /// reference rather than a 40-char SHA wall.
    private var shortRevision: String {
        String(descriptor.revision.prefix(8))
    }

    private var parameterCountRow: InfoRow? {
        guard let count = descriptor.performance.parameterCount else { return nil }
        let formatted: String
        if count >= 1_000_000_000 {
            formatted = "\(count / 1_000_000_000)B"
        } else if count >= 1_000_000 {
            formatted = "\(count / 1_000_000)M"
        } else {
            formatted = "\(count)"
        }
        return InfoRow(title: "Parameters", value: formatted, monospaced: false)
    }

    // MARK: - Human-friendly meta rows
    //
    // Shown below the hero Speed / Accuracy / Size trio in the redesigned
    // popover. Each row is only included when the descriptor declares the
    // corresponding optional field, so models without metadata don't show
    // empty rows.

    /// Ordered list of human-friendly label–value pairs for the popover's
    /// lower section. Only rows with non-nil values are included.
    var humanFriendlyRows: [InfoRow] {
        var rows: [InfoRow] = []
        if let v = descriptor.madeBy {
            rows.append(InfoRow(title: "Made by", value: v, monospaced: false))
        }
        if let v = descriptor.worksWith {
            rows.append(InfoRow(title: "Works with", value: v, monospaced: false))
        }
        if let v = descriptor.goodFor {
            rows.append(InfoRow(title: "Good for", value: v, monospaced: false))
        }
        // Model type is derived from the descriptor's kind, not stored
        // as a raw string, so we compute it here.
        rows.append(InfoRow(title: "Model type", value: modelTypeLabel, monospaced: false))
        if let v = descriptor.license {
            rows.append(InfoRow(title: "License", value: v, monospaced: false))
        }
        return rows
    }

    private var modelTypeLabel: String {
        let capabilities = descriptor.engine.capabilities
        if capabilities == [.asr, .streamingASR] {
            return "Voice · Offline + Streaming"
        }
        switch ModelKind.allCases.first(where: capabilities.contains) {
        case .asr:
            return "Voice · Offline"
        case .streamingASR:
            return "Voice · Streaming"
        case .diarization:
            return "Diarization · Offline"
        case .vad:
            return "Voice activity detection"
        case .tts:
            return "Text-to-speech"
        case nil:
            return "Model"
        }
    }
}
