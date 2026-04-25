import Foundation
import PersonalScribeCore

public protocol ModelBoundTranscriberProviding: Sendable {
    func transcriber(for descriptor: ModelDescriptor) -> any Transcriber
}
