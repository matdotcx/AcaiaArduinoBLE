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

    func begin() {
        guard session == nil else { return }
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start()
        self.session = session
    }

    func end() {
        session?.invalidate()
        session = nil
    }

    // MARK: WKExtendedRuntimeSessionDelegate

    func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {}

    func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {
        // About to expire — drop our handle so `begin()` can start a fresh session.
        if self.session === session { self.session = nil }
    }

    func extendedRuntimeSession(
        _ session: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        if self.session === session { self.session = nil }
    }
}
