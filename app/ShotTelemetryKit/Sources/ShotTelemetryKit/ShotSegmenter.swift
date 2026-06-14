import Foundation

/// Pure state machine that turns a stream of telemetry frames into shot
/// boundaries, using the frame `state` field. No persistence, no I/O — so it is
/// fully unit-testable. `ShotRecorder` wraps it with SwiftData.
///
/// Firmware emits: `idle` between shots, `brew` during, and one `done` at the
/// end. We open a shot on the first `brew`, append every `brew`/`done` sample,
/// and close on `done`. As a safety net, if a fresh `brew` arrives with the
/// shot timer reset (a `done` we never saw — e.g. a BLE drop), we close the
/// previous shot and start a new one.
public struct ShotSegmenter {

    public enum EndReason: Equatable {
        case done            // clean end — saw the firmware's done frame
        case newShotStarted  // inferred — timer reset without a done
    }

    public enum Event: Equatable {
        case began
        case sample(TelemetryFrame)
        case ended(reason: EndReason)
    }

    public private(set) var isInShot = false
    private var lastTMs: UInt32 = 0

    public init() {}

    public mutating func process(_ frame: TelemetryFrame) -> [Event] {
        var events: [Event] = []

        switch frame.state {
        case .brew:
            // Timer ran backwards while we thought a shot was active → we missed
            // the previous `done`. Close it before opening the new one.
            if isInShot && frame.tMs < lastTMs {
                events.append(.ended(reason: .newShotStarted))
                isInShot = false
            }
            if !isInShot {
                isInShot = true
                events.append(.began)
            }
            events.append(.sample(frame))
            lastTMs = frame.tMs

        case .done:
            if isInShot {
                events.append(.sample(frame))
                events.append(.ended(reason: .done))
                isInShot = false
            }

        case .idle, .preinfuse, .settle, .unknown:
            break // not part of a recorded shot
        }

        return events
    }
}
