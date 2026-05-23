import Foundation
import PersonalScribeCore

public final class DiarizedTurnTranscriptionProcessor: @unchecked Sendable, Processor {
    private let diarizer: any SpeakerDiarizer
    private let transcriber: any Transcriber
    private let sensitivity: SpeakerSeparationSensitivity
    private let languageHint: String?
    private let logger: PersonalScribeLogger?
    private let lock = NSLock()

    private var hasPreparedModel = false
    private var prepareTask: Task<Void, Error>?

    public convenience init(
        diarizer: any SpeakerDiarizer,
        transcriber: any Transcriber,
        sensitivity: SpeakerSeparationSensitivity = .balanced,
        languageHint: String? = nil
    ) {
        self.init(
            diarizer: diarizer,
            transcriber: transcriber,
            sensitivity: sensitivity,
            languageHint: languageHint,
            logger: nil
        )
    }

    package init(
        diarizer: any SpeakerDiarizer,
        transcriber: any Transcriber,
        sensitivity: SpeakerSeparationSensitivity = .balanced,
        languageHint: String? = nil,
        logger: PersonalScribeLogger? = nil
    ) {
        self.diarizer = diarizer
        self.transcriber = transcriber
        self.sensitivity = sensitivity
        self.languageHint = languageHint
        self.logger = logger
    }

    public func prepare() async throws {
        let task = lock.withLock { () -> Task<Void, Error>? in
            if hasPreparedModel {
                return nil
            }

            if let prepareTask {
                return prepareTask
            }

            let diarizer = self.diarizer
            let transcriber = self.transcriber
            let sensitivity = self.sensitivity
            let task = Task {
                await diarizer.applySensitivity(sensitivity)
                async let prepareDiarizer: Void = diarizer.prepare()
                async let prepareTranscriber: Void = transcriber.prepare()
                try await prepareDiarizer
                try await prepareTranscriber
            }
            prepareTask = task
            return task
        }

        guard let task else {
            return
        }

        do {
            try await task.value
            lock.withLock {
                hasPreparedModel = true
                prepareTask = nil
            }
        } catch {
            lock.withLock {
                prepareTask = nil
            }
            throw error
        }
    }

    public func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        let diarizerProgress = diarizer.modelDownloadProgress()
        let transcriberProgress = transcriber.modelDownloadProgress()

        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await snapshot in diarizerProgress {
                            continuation.yield(snapshot)
                        }
                    }
                    group.addTask {
                        for await snapshot in transcriberProgress {
                            continuation.yield(snapshot)
                        }
                    }
                    await group.waitForAll()
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func process(
        audio: PCMBuffer,
        priors: [ProcessorOutput]
    ) async throws -> ProcessorOutput {
        try await prepare()

        let priorTurns = priorTurnsStream(from: priors)
        let diarizationStream = priorTurns ?? diarizer.diarize(audio)
        let usedPriorTurns = priorTurns != nil
        var processedTurns: [SpeakerTurn] = []
        var transcribedTurns: [TurnTranscription] = []
        var skippedEmptySliceCount = 0

        for await event in diarizationStream {
            // Surface adapter-side failures rather than collapsing them
            // into an empty transcript. The orchestrator catches this
            // and publishes `.error(.transcriptionFailure)` to the
            // session snapshot so the pill + response card render the
            // failure instead of returning a silent empty result.
            if case .failed = event {
                throw PersonalScribeError.transcriptionFailure
            }
            let finalizedTurns = Self.finalizedTurns(from: event)
            let pendingTurns = finalizedTurns
                .filter { turn in
                    processedTurns.contains(turn) == false
                }
                .sorted(by: Self.turnsAreOrdered)

            for turn in pendingTurns {
                processedTurns.append(turn)

                let slice = try PCMBufferSlicing.slice(
                    audio,
                    from: turn.start,
                    to: turn.end,
                    sampleRate: audio.sampleRate
                )
                guard !slice.samples.isEmpty else {
                    skippedEmptySliceCount += 1
                    continue
                }

                let prepared = try Self.preparedTurnAudio(from: slice)
                let result = try await transcriber.transcribe(
                    prepared.buffer,
                    languageHint: languageHint
                )
                transcribedTurns.append(
                    TurnTranscription(
                        turn: turn,
                        result: Self.clamped(result, to: prepared.originalDuration)
                    )
                )
            }
        }

        let result = Self.aggregate(transcribedTurns, audioDuration: audio.duration)
        logger?.info(
            "diarized_processor_summary — usedPriorTurns=\(usedPriorTurns) finalizedTurnCount=\(processedTurns.count) transcribedTurnCount=\(transcribedTurns.count) skippedEmptySliceCount=\(skippedEmptySliceCount) textLength=\(result.text.count) segmentCount=\(result.segments.count) audioDurationMs=\(Self.milliseconds(result.audioDuration))"
        )
        return .text(result)
    }
}

private extension DiarizedTurnTranscriptionProcessor {
    struct TurnTranscription {
        let turn: SpeakerTurn
        let result: TranscriptionResult
    }

    struct PreparedTurnAudio {
        let buffer: PCMBuffer
        let originalDuration: Duration
    }

    static let minimumPerTurnASRDuration: Duration = .seconds(1)

    static func finalizedTurns(from event: SpeakerDiarizationEvent) -> [SpeakerTurn] {
        switch event {
        case .update(_, let finalized):
            finalized
        case .terminal(let turns):
            turns
        case .failed:
            []
        }
    }

    static func turnsAreOrdered(_ lhs: SpeakerTurn, _ rhs: SpeakerTurn) -> Bool {
        if lhs.start != rhs.start {
            return lhs.start < rhs.start
        }
        if lhs.end != rhs.end {
            return lhs.end < rhs.end
        }
        return lhs.speakerID < rhs.speakerID
    }

    static func preparedTurnAudio(from slice: PCMBuffer) throws -> PreparedTurnAudio {
        let minimumFrameCount = Int(ceil(seconds(minimumPerTurnASRDuration) * slice.sampleRate))
        guard slice.frameCount < minimumFrameCount else {
            return PreparedTurnAudio(buffer: slice, originalDuration: slice.duration)
        }

        let missingFrameCount = minimumFrameCount - slice.frameCount
        let padded = try PCMBuffer(
            samples: slice.samples + Array(
                repeating: 0,
                count: missingFrameCount * slice.channelCount
            ),
            sampleRate: slice.sampleRate,
            channelCount: slice.channelCount,
            timestamp: slice.timestamp
        )
        return PreparedTurnAudio(buffer: padded, originalDuration: slice.duration)
    }

    static func clamped(
        _ result: TranscriptionResult,
        to originalDuration: Duration
    ) -> TranscriptionResult {
        let segments = result.segments.compactMap { segment -> TranscriptionResult.Segment? in
            let start = clamped(segment.start, to: originalDuration)
            let end = clamped(segment.end, lowerBound: start, upperBound: originalDuration)
            guard end > start else {
                return nil
            }
            return .init(text: segment.text, start: start, end: end)
        }
        let tokenTimings = result.tokenTimings?.compactMap { timing -> TokenTiming? in
            let start = clamped(timing.start, to: originalDuration)
            let end = clamped(timing.end, lowerBound: start, upperBound: originalDuration)
            guard end > start else {
                return nil
            }
            return TokenTiming(
                token: timing.token,
                start: start,
                end: end,
                confidence: timing.confidence
            )
        }

        return TranscriptionResult(
            text: result.text,
            segments: segments,
            audioDuration: originalDuration,
            processingDuration: result.processingDuration,
            confidence: result.confidence,
            tokenTimings: tokenTimings,
            performanceMetrics: result.performanceMetrics,
            ctcDetectedTerms: result.ctcDetectedTerms,
            ctcAppliedTerms: result.ctcAppliedTerms
        )
    }

    static func aggregate(
        _ turnResults: [TurnTranscription],
        audioDuration: Duration
    ) -> TranscriptionResult {
        let labeledLines = labeledTurnLines(from: turnResults)
        let segments = turnResults
            .flatMap(offsetSegments(for:))
            .sorted(by: segmentsAreOrdered)
        let confidences = turnResults.compactMap(\.result.confidence)
        let confidence = confidences.isEmpty
            ? nil
            : confidences.reduce(0, +) / Float(confidences.count)
        let tokenTimings = flattenedTokenTimings(from: turnResults)
        let performanceMetrics = aggregatePerformanceMetrics(from: turnResults)
        let detectedTerms = orderedUnion(turnResults.compactMap(\.result.ctcDetectedTerms).flatMap { $0 })
        let appliedTerms = orderedUnion(turnResults.compactMap(\.result.ctcAppliedTerms).flatMap { $0 })

        return TranscriptionResult(
            text: labeledLines.joined(separator: "\n\n"),
            segments: segments,
            audioDuration: audioDuration,
            processingDuration: turnResults.reduce(.zero) { partialResult, turnResult in
                partialResult + turnResult.result.processingDuration
            },
            confidence: confidence,
            tokenTimings: tokenTimings.isEmpty ? nil : tokenTimings,
            performanceMetrics: performanceMetrics,
            ctcDetectedTerms: detectedTerms.isEmpty ? nil : detectedTerms,
            ctcAppliedTerms: appliedTerms.isEmpty ? nil : appliedTerms
        )
    }

    // Assigns "Speaker N" labels by order of first appearance — vendor IDs
    // are not guaranteed contiguous or zero-indexed, so we map them to
    // 1-indexed display numbers as we walk the turn results. Empty-text
    // turns are skipped and do not consume a label slot.
    static func labeledTurnLines(from turnResults: [TurnTranscription]) -> [String] {
        var labelByVendorID: [String: Int] = [:]
        var nextLabelNumber = 1
        return turnResults.compactMap { turnResult -> String? in
            let text = turnResult.result.text
            guard text.isEmpty == false else { return nil }
            let vendorID = turnResult.turn.speakerID
            let labelNumber: Int
            if let existing = labelByVendorID[vendorID] {
                labelNumber = existing
            } else {
                labelNumber = nextLabelNumber
                labelByVendorID[vendorID] = labelNumber
                nextLabelNumber += 1
            }
            return "Speaker \(labelNumber): \(text)"
        }
    }

    static func offsetSegments(
        for turnResult: TurnTranscription
    ) -> [TranscriptionResult.Segment] {
        if turnResult.result.segments.isEmpty {
            guard turnResult.result.text.isEmpty == false else {
                return []
            }

            return [
                .init(
                    text: turnResult.result.text,
                    start: turnResult.turn.start,
                    end: turnResult.turn.end
                ),
            ]
        }

        return turnResult.result.segments.map { segment in
            .init(
                text: segment.text,
                start: turnResult.turn.start + segment.start,
                end: turnResult.turn.start + segment.end
            )
        }
    }

    static func segmentsAreOrdered(
        _ lhs: TranscriptionResult.Segment,
        _ rhs: TranscriptionResult.Segment
    ) -> Bool {
        if lhs.start != rhs.start {
            return lhs.start < rhs.start
        }
        if lhs.end != rhs.end {
            return lhs.end < rhs.end
        }
        return lhs.text < rhs.text
    }

    static func clamped(_ duration: Duration, to upperBound: Duration) -> Duration {
        clamped(duration, lowerBound: .zero, upperBound: upperBound)
    }

    static func clamped(
        _ duration: Duration,
        lowerBound: Duration,
        upperBound: Duration
    ) -> Duration {
        min(max(duration, lowerBound), upperBound)
    }

    static func flattenedTokenTimings(
        from turnResults: [TurnTranscription]
    ) -> [TokenTiming] {
        turnResults.flatMap { turnResult -> [TokenTiming] in
            guard let tokenTimings = turnResult.result.tokenTimings else {
                return []
            }

            return tokenTimings.map { tokenTiming in
                TokenTiming(
                    token: tokenTiming.token,
                    start: turnResult.turn.start + tokenTiming.start,
                    end: turnResult.turn.start + tokenTiming.end,
                    confidence: tokenTiming.confidence
                )
            }
        }
    }

    static func aggregatePerformanceMetrics(
        from turnResults: [TurnTranscription]
    ) -> TranscriberPerformanceMetrics? {
        let loadDuration = turnResults.compactMap { $0.result.performanceMetrics?.loadDuration }.first
        let encodeDuration = sum(turnResults.compactMap { $0.result.performanceMetrics?.encodeDuration })
        let decodeDuration = sum(turnResults.compactMap { $0.result.performanceMetrics?.decodeDuration })
        let totalDuration = sum(turnResults.compactMap { $0.result.performanceMetrics?.totalDuration })

        guard
            loadDuration != nil
                || encodeDuration != nil
                || decodeDuration != nil
                || totalDuration != nil
        else {
            return nil
        }

        return TranscriberPerformanceMetrics(
            loadDuration: loadDuration,
            encodeDuration: encodeDuration,
            decodeDuration: decodeDuration,
            totalDuration: totalDuration
        )
    }

    static func sum(_ durations: [Duration]) -> Duration? {
        guard durations.isEmpty == false else {
            return nil
        }

        return durations.reduce(.zero, +)
    }

    static func orderedUnion(_ terms: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        for term in terms where seen.insert(term).inserted {
            ordered.append(term)
        }

        return ordered
    }

    static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        let attosecondsPerSecond = 1_000_000_000_000_000_000.0
        return Double(components.seconds) + (Double(components.attoseconds) / attosecondsPerSecond)
    }

    static func milliseconds(_ duration: Duration) -> Int {
        Int((seconds(duration) * 1000).rounded())
    }

    func priorTurnsStream(
        from priors: [ProcessorOutput]
    ) -> AsyncStream<SpeakerDiarizationEvent>? {
        for prior in priors.reversed() {
            if case .turns(let stream) = prior {
                return stream
            }
        }

        return nil
    }
}
