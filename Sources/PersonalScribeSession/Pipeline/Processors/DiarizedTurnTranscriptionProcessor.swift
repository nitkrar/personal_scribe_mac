import Foundation
import PersonalScribeCore

public final class DiarizedTurnTranscriptionProcessor: @unchecked Sendable, Processor {
    private let diarizer: any SpeakerDiarizer
    private let transcriber: any Transcriber2
    private let lock = NSLock()

    private var hasPreparedModel = false
    private var prepareTask: Task<Void, Error>?

    public init(
        diarizer: any SpeakerDiarizer,
        transcriber: any Transcriber2
    ) {
        self.diarizer = diarizer
        self.transcriber = transcriber
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
            let task = Task {
                async let prepareDiarizer = diarizer.prepare()
                async let prepareTranscriber = transcriber.prepare()
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

        let diarizationStream = priorTurnsStream(from: priors) ?? diarizer.diarize(audio)
        var processedTurns: [SpeakerTurn] = []
        var transcribedTurns: [TurnTranscription] = []

        for await event in diarizationStream {
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
                    continue
                }

                let result = try await transcriber.transcribe(slice)
                transcribedTurns.append(
                    TurnTranscription(
                        turn: turn,
                        result: result
                    )
                )
            }
        }

        return .text(Self.aggregate(transcribedTurns, audioDuration: audio.duration))
    }
}

private extension DiarizedTurnTranscriptionProcessor {
    struct TurnTranscription {
        let turn: SpeakerTurn
        let result: TranscriptionResult
    }

    static func finalizedTurns(from event: SpeakerDiarizationEvent) -> [SpeakerTurn] {
        switch event {
        case .update(_, let finalized):
            finalized
        case .terminal(let turns):
            turns
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

    static func aggregate(
        _ turnResults: [TurnTranscription],
        audioDuration: Duration
    ) -> TranscriptionResult {
        let texts = turnResults.map(\.result.text).filter { $0.isEmpty == false }
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
            text: texts.joined(separator: "\n"),
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

    static func flattenedTokenTimings(
        from turnResults: [TurnTranscription]
    ) -> [TokenTiming] {
        turnResults.flatMap { turnResult in
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
