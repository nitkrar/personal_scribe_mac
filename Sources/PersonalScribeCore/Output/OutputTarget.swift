public enum OutputTarget: CaseIterable, Equatable, Sendable {
    case frontmostApp
    case clipboardOnly
    case selfFrontmost
    /// Left on the clipboard because Accessibility (needed to post ⌘V)
    /// isn't granted.
    case clipboardNeedsAccessibility
}
