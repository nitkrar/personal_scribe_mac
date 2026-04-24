import AppKit
import Foundation

/// Unified snapshot + restore of the system pasteboard, covering both the
/// pill UX's Cancel Card Undo affordance (a durable session-lifecycle slot)
/// and the `ClipboardBatchOutput` auto-restore timer (transient per-paste
/// handles). Replaces the pre-#072 split where `PasteboardSnapshotService`
/// held a string-only slot for Undo and `ClipboardBatchOutput.deliverBatch`
/// held an inline `[NSPasteboardItem]` local for auto-restore — parallel
/// implementations of the same concept. See `plans/072_snapshot_unification/`.
///
/// # Two-token model (Step 2 prerequisite)
///
/// The service owns the pasteboard write boundary through
/// `replaceContents(with:)`. A successful write returns a
/// `ClipboardWriteToken` carrying the post-write `changeCount`. The output
/// pipeline captures a transient snapshot (pre-write clipboard) *and* a
/// write token (post-write checkpoint); when the delayed restore fires,
/// `restoreSnapshotIfUnchanged(_:token:)` compares the current
/// `changeCount` with the write token — only restoring if nothing
/// else has touched the clipboard since our write landed. The guard
/// itself ships unwired in Step 1; Step 2 flips the call site.
///
/// # Empty snapshots are real snapshots
///
/// Capturing with nothing on the pasteboard yields a valid (empty)
/// snapshot; restoring an empty snapshot clears the pasteboard. Matches
/// the pre-#072 auto-restore semantic (`restorePasteboard([])` cleared
/// and wrote nothing); the previous Undo path silently turned "no
/// string" into a no-op — that was a scope cut, not an invariant.
@MainActor
public final class PasteboardSnapshotService {
    public enum Slot: Hashable, Sendable {
        /// Pre-recording pasteboard contents captured on `idle → recording`
        /// and consumed on Cancel Card Undo.
        case cancelUndo
    }

    /// Opaque receipt for a transient snapshot. Must be returned to the
    /// service's `restoreSnapshot(_:)`, `restoreSnapshotIfUnchanged(_:token:)`,
    /// or `discardSnapshot(_:)`. Not constructible by callers outside this
    /// file — the only way to obtain one is `captureTransientSnapshot()`.
    public struct Handle: Hashable, Sendable {
        fileprivate let id: UUID
    }

    public typealias ItemsReader = @MainActor () -> [NSPasteboardItem]
    public typealias ItemsWriter = @MainActor ([NSPasteboardItem]) -> Void
    public typealias StringWriter = @MainActor (String) -> Bool
    public typealias ChangeCountReader = @MainActor () -> Int

    private let itemsReader: ItemsReader
    private let itemsWriter: ItemsWriter
    private let stringWriter: StringWriter
    private let changeCountReader: ChangeCountReader

    private var slotSnapshots: [Slot: [NSPasteboardItem]] = [:]
    private var transientSnapshots: [UUID: [NSPasteboardItem]] = [:]

    public convenience init(pasteboard: NSPasteboard = .general) {
        self.init(
            itemsReader: { Self.liveReadItems(from: pasteboard) },
            itemsWriter: { Self.liveWriteItems($0, to: pasteboard) },
            stringWriter: { Self.liveWriteString($0, to: pasteboard) },
            changeCountReader: { pasteboard.changeCount }
        )
    }

    init(
        itemsReader: @escaping ItemsReader,
        itemsWriter: @escaping ItemsWriter,
        stringWriter: @escaping StringWriter,
        changeCountReader: @escaping ChangeCountReader
    ) {
        self.itemsReader = itemsReader
        self.itemsWriter = itemsWriter
        self.stringWriter = stringWriter
        self.changeCountReader = changeCountReader
    }

    // MARK: - Durable slots

    public func captureCurrentContents(into slot: Slot) {
        slotSnapshots[slot] = Self.deepCopy(itemsReader())
    }

    @discardableResult
    public func restoreSnapshot(from slot: Slot) -> Bool {
        guard let items = slotSnapshots.removeValue(forKey: slot) else {
            return false
        }
        itemsWriter(items)
        return true
    }

    public func clearSnapshot(in slot: Slot) {
        slotSnapshots.removeValue(forKey: slot)
    }

    // MARK: - Transient handles

    public func captureTransientSnapshot() -> Handle {
        let handle = Handle(id: UUID())
        transientSnapshots[handle.id] = Self.deepCopy(itemsReader())
        return handle
    }

    @discardableResult
    public func restoreSnapshot(_ handle: Handle) -> Bool {
        guard let items = transientSnapshots.removeValue(forKey: handle.id) else {
            return false
        }
        itemsWriter(items)
        return true
    }

    /// Restore the snapshot referenced by `handle` **only if** the
    /// pasteboard's current `changeCount` still matches `token.changeCount`
    /// — i.e., nothing has written to the clipboard since the token was
    /// minted by `replaceContents(with:)`. The handle is consumed in both
    /// branches (match vs. mismatch). Returns `true` when restore actually
    /// wrote.
    @discardableResult
    public func restoreSnapshotIfUnchanged(
        _ handle: Handle,
        token: ClipboardWriteToken
    ) -> Bool {
        guard let items = transientSnapshots.removeValue(forKey: handle.id) else {
            return false
        }
        guard changeCountReader() == token.changeCount else {
            return false
        }
        itemsWriter(items)
        return true
    }

    public func discardSnapshot(_ handle: Handle) {
        transientSnapshots.removeValue(forKey: handle.id)
    }

    // MARK: - Write boundary

    /// The only sanctioned path for writing a transcript string to the
    /// pasteboard. Clears existing contents, writes `string` as `.string`,
    /// and returns a `ClipboardWriteToken` carrying the post-write
    /// `changeCount`. Returns `nil` only when the underlying write fails
    /// (preserves `ClipboardBatchOutput`'s pre-refactor rollback signal).
    public func replaceContents(with string: String) -> ClipboardWriteToken? {
        guard stringWriter(string) else {
            return nil
        }
        return ClipboardWriteToken(changeCount: changeCountReader())
    }

    // MARK: - Helpers

    private static func deepCopy(_ items: [NSPasteboardItem]) -> [NSPasteboardItem] {
        items.map { source in
            let copy = NSPasteboardItem()
            for type in source.types {
                if let data = source.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private static func liveReadItems(from pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        deepCopy(pasteboard.pasteboardItems ?? [])
    }

    private static func liveWriteItems(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private static func liveWriteString(_ string: String, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(string, forType: .string)
    }
}

/// Opaque post-write checkpoint minted by
/// `PasteboardSnapshotService.replaceContents(with:)`. Carries the
/// pasteboard's `changeCount` at the moment the transcript write landed.
/// Consumers pass it back to `restoreSnapshotIfUnchanged(_:token:)` so the
/// service can tell whether our write is still the most recent.
public struct ClipboardWriteToken: Equatable, Sendable {
    fileprivate let changeCount: Int
}
