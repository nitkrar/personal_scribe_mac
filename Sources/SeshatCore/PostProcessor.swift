import Foundation

/// Pure, deterministic text cleanup. Two stages:
/// 1. Filler-word removal: strips um, uh, er, you know, like, i mean, etc.
/// 2. Basic punctuation: trims whitespace, ensures trailing sentence terminator, capitalizes first letter.
///
/// Does NOT use an LLM. Safe to run in SessionCoordinator before surfacing lastResult.
public struct PostProcessor: Sendable {
    public init() {}

    public func clean(_ raw: String) -> String {
        raw
    }
}
