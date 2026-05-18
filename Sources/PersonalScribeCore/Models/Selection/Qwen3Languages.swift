import Foundation

/// Shared Qwen3-ASR language registry, derived on 2026-05-18 from
/// FluidAudio's `Qwen3AsrConfig.Language` enum. This list stays in the
/// Core layer as the vendor-independent BCP-47 surface exposed to the
/// settings UI and preference store.
public enum Qwen3Languages {
    public static let codes: [String] = [
        "ar", "cs", "da", "de", "el", "en", "es", "fa", "fi", "fil",
        "fr", "hi", "hu", "id", "it", "ja", "ko", "mk", "ms", "nl",
        "pl", "pt", "ro", "ru", "sv", "th", "tr", "vi", "yue", "zh",
    ]
}
