import AppKit
import Foundation

/// Snapshot and restore of the system pasteboard for
/// `ClipboardBatchOutput`'s delayed restore.
///
/// # Two-token model
///
/// The service owns the pasteboard write boundary through
/// `replaceContents(with:)`. A successful write returns a
/// `ClipboardWriteToken` carrying the post-write `changeCount`. The output
/// pipeline captures a transient snapshot (pre-write clipboard) *and* a
/// write token (post-write checkpoint); when the delayed restore fires,
/// `restoreSnapshotIfUnchanged(_:token:)` compares the current
/// `changeCount` with the write token, restoring only if nothing else
/// has touched the clipboard since the transcript write.
///
/// # Empty snapshots are real snapshots
///
/// Capturing with nothing on the pasteboard yields a valid (empty)
/// snapshot; restoring an empty snapshot clears the pasteboard.
@MainActor
public final class PasteboardSnapshotService {
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
    /// `changeCount`. Returns `nil` only when the underlying write fails.
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
