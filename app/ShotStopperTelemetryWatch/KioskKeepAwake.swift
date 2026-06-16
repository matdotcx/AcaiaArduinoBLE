import Foundation
import WatchKit

/// Keeps the watch app frontmost with the screen on during use, via a
/// `WKExtendedRuntimeSession`. The mounted-on-the-machine kiosk would otherwise
/// dim and return to the clock after ~70 s of inactivity.
///
/// Requires `WKBackgroundModes` to contain `self-care` in this target's Info.plist
/// (already set). Sessions are time-bounded by watchOS; we restart on expiry.
final class KioskKeepAwake: NSObject, WKExtendedRuntimeSessionDelegate {
    private var session: WKExtendedRuntimeSession?
    /// Whether the kiosk should currently be kept awake. `end()` clears it so an
    /// in-flight expiry callback can't respawn a session after we've stopped.
    private var wantAwake = false

    func begin() {
        wantAwake = true
        guard session == nil else { return }
        startSession()
    }

    func end() {
        wantAwake = false
        session?.invalidate()
        session = nil
    }

    private func startSession() {
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start()
        self.session = session
    }

    // MARK: WKExtendedRuntimeSessionDelegate

    func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {}

    func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {
        // watchOS bounds each session's lifetime. Start a replacement before this
        // one ends so the mounted kiosk keeps its screen on past the window.
        guard self.session === session else { return }
        self.session = nil
        if wantAwake { startSession() }
    }

    func extendedRuntimeSession(
        _ session: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        // Drop our handle on invalidation. We deliberately do NOT respawn here:
        // `willExpire` is the clean "about to time out" path; invalidations from
        // errors or resigning frontmost should not loop a new session.
        if self.session === session { self.session = nil }
    }
}
