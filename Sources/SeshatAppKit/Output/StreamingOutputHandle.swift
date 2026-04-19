import Foundation
import SeshatCore

@MainActor
final class StreamingOutputHandle: OutputStreamHandle, @unchecked Sendable {
    enum TransportSelection {
        case decisionRequired
        case resolved(OutputDelivery)
    }

    private let transportSelection: TransportSelection
    private let onAppendChunk: @MainActor (String) -> Void
    private let onFinalizeChunks: @MainActor ([String]) -> Void

    private(set) var appendedChunks: [String] = []
    private(set) var finalizedChunks: [String] = []
    private(set) var finalizedDelivery: OutputDelivery?
    private(set) var finalizationError: OutputError?
    private(set) var isFinalized = false

    static func live() -> StreamingOutputHandle {
        StreamingOutputHandle(transportSelection: .decisionRequired)
    }

    init(
        transportSelection: TransportSelection = .decisionRequired,
        onAppendChunk: @escaping @MainActor (String) -> Void = { _ in },
        onFinalizeChunks: @escaping @MainActor ([String]) -> Void = { _ in }
    ) {
        self.transportSelection = transportSelection
        self.onAppendChunk = onAppendChunk
        self.onFinalizeChunks = onFinalizeChunks
    }

    func append(_ chunk: String) {
        guard !isFinalized else { return }

        appendedChunks.append(chunk)
        onAppendChunk(chunk)
    }

    func finalize() {
        guard !isFinalized else { return }

        isFinalized = true
        finalizedChunks = appendedChunks

        switch transportSelection {
        case .decisionRequired:
            finalizationError = .streamingTransportDecisionRequired
        case .resolved(let delivery):
            finalizedDelivery = delivery
            onFinalizeChunks(finalizedChunks)
        }
    }
}
