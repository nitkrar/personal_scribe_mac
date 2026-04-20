import Foundation

@MainActor
enum MicrophonePermissionState: Equatable {
    case notYetRequested
    case granted
    case denied
}
