import Foundation
import PersonalScribeCore

struct AdapterRecord: Sendable {
    let descriptorID: String
    let transcriber: (any Transcriber)?
    let streamingTranscriber: (any StreamingTranscriber)?
    let diarizer: (any SpeakerDiarizer)?

    init(descriptorID: String, transcriber: any Transcriber) {
        self.descriptorID = descriptorID
        self.transcriber = transcriber
        self.streamingTranscriber = nil
        self.diarizer = nil
    }

    init(descriptorID: String, streamingTranscriber: any StreamingTranscriber) {
        self.descriptorID = descriptorID
        self.transcriber = nil
        self.streamingTranscriber = streamingTranscriber
        self.diarizer = nil
    }

    init(
        descriptorID: String,
        transcriber: any Transcriber,
        streamingTranscriber: any StreamingTranscriber
    ) {
        self.descriptorID = descriptorID
        self.transcriber = transcriber
        self.streamingTranscriber = streamingTranscriber
        self.diarizer = nil
    }

    init(descriptorID: String, diarizer: any SpeakerDiarizer) {
        self.descriptorID = descriptorID
        self.transcriber = nil
        self.streamingTranscriber = nil
        self.diarizer = diarizer
    }

    var lifecycle: any ModelLifecycle {
        if let transcriber {
            return transcriber
        }

        if let streamingTranscriber {
            return streamingTranscriber
        }

        if let diarizer {
            return diarizer
        }

        preconditionFailure("AdapterRecord requires one bound adapter")
    }

    var lifecycles: [any ModelLifecycle] {
        var values: [any ModelLifecycle] = []
        if let transcriber {
            values.append(transcriber)
        }
        if let streamingTranscriber {
            values.append(streamingTranscriber)
        }
        if let diarizer {
            values.append(diarizer)
        }
        return values
    }
}
