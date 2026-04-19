import Foundation
import SeshatCore

typealias StreamingOutputHandleFactory = @MainActor () -> any OutputStreamHandle

@MainActor
public final class AppKitOutputService: OutputService, @unchecked Sendable {
    private let pasteService: any PasteOutputServing
    private let copyService: any CopyOutputServing
    private let streamingHandleFactory: StreamingOutputHandleFactory

    public init() {
        self.pasteService = PasteOutputService()
        self.copyService = CopyOutputService()
        self.streamingHandleFactory = {
            StreamingOutputHandle.live()
        }
    }

    init(
        pasteService: any PasteOutputServing,
        copyService: any CopyOutputServing,
        streamingHandleFactory: @escaping StreamingOutputHandleFactory
    ) {
        self.pasteService = pasteService
        self.copyService = copyService
        self.streamingHandleFactory = streamingHandleFactory
    }

    public func paste(text: String) async throws {
        try await pasteService.paste(text: text)
    }

    public func copy(text: String) async throws {
        try await copyService.copy(text: text)
    }

    public func beginStream() -> any OutputStreamHandle {
        streamingHandleFactory()
    }
}
