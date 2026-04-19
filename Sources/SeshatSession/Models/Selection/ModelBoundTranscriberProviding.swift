import Foundation
import SeshatCore

public protocol ModelBoundTranscriberProviding: Sendable {
    func transcriber(for descriptor: ModelDescriptor) -> any Transcribing
}
