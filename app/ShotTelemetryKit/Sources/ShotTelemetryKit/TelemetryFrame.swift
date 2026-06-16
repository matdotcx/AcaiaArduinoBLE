import Foundation

/// One decoded 16-byte telemetry frame. See `docs/GATT_DESIGN.md` for the wire layout.
///
/// Bytes are assembled explicitly (not `load(as:)`) so decoding is correct
/// regardless of host alignment, and independent of `Data` slice indices.
public struct TelemetryFrame: Equatable, Sendable {

    public enum State: UInt8, Sendable, Equatable {
        case idle = 0
        case preinfuse = 1   // reserved — firmware does not emit yet
        case brew = 2
        case settle = 3      // reserved — firmware does not emit yet
        case done = 4
        case unknown = 255

        init(raw: UInt8) { self = State(rawValue: raw) ?? .unknown }
    }

    /// Why the shot ended. Sent by the firmware in `flags` bits 2-4 on the final
    /// (`done`) frame only. Wire value is the firmware `ENDTYPE` + 1, so 0 cleanly
    /// means "not reported" (legacy firmware or any non-done frame).
    public enum EndReason: UInt8, Sendable, Equatable {
        case none = 0        // not reported (legacy / non-done frame)
        case button = 1      // user dropped the paddle / pressed stop → CUT SHORT
        case weight = 2      // hit the target weight                  → ON TARGET
        case time = 3        // hit max shot duration                  → OVERRUN
        case disconnect = 4  // scale dropped mid-shot
    }

    public let tMs: UInt32
    public let weightG: Float
    public let flowGps: Float
    public let state: State
    /// The raw state byte, preserved even when `state == .unknown`.
    public let rawState: UInt8
    public let flags: UInt8
    public let setpointCg: UInt16

    // Derived conveniences.
    public var elapsed: TimeInterval { Double(tMs) / 1000 }
    public var setpointG: Float { Float(setpointCg) / 100 }
    public var scaleConnected: Bool { flags & 0x01 != 0 }
    public var setpointReached: Bool { flags & 0x02 != 0 }
    /// Firmware has latched a latching-switch shot and is waiting for the paddle to be
    /// returned to home (flags bit 5). False on momentary machines and once returned/ended.
    public var awaitingPaddleReturn: Bool { flags & 0x20 != 0 }
    /// End reason packed in flags bits 2-4 (meaningful on the `done` frame).
    public var endReason: EndReason { EndReason(rawValue: (flags >> 2) & 0x07) ?? .none }

    /// Decode a notify payload. Returns `nil` if it is shorter than 16 bytes.
    public init?(_ data: Data) {
        guard data.count >= 16 else { return nil }
        let b = [UInt8](data) // reindexes any slice to 0-based

        func u32(_ i: Int) -> UInt32 {
            UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
        }
        func u16(_ i: Int) -> UInt16 {
            UInt16(b[i]) | UInt16(b[i + 1]) << 8
        }

        self.tMs = u32(0)
        self.weightG = Float(bitPattern: u32(4))
        self.flowGps = Float(bitPattern: u32(8))
        self.rawState = b[12]
        self.state = State(raw: b[12])
        self.flags = b[13]
        self.setpointCg = u16(14)
    }

    /// Build a wire-format frame. Used by tests, SwiftUI previews, and a mock
    /// device; mirrors `sendTelemetryFrame()` in the firmware byte-for-byte.
    public static func encode(
        tMs: UInt32,
        weightG: Float,
        flowGps: Float,
        state: State,
        scaleConnected: Bool,
        setpointReached: Bool,
        setpointG: Float,
        endReason: EndReason = .none,
        awaitingPaddleReturn: Bool = false
    ) -> Data {
        var b = [UInt8](repeating: 0, count: 16)

        func putU32(_ v: UInt32, _ i: Int) {
            b[i] = UInt8(v & 0xFF)
            b[i + 1] = UInt8((v >> 8) & 0xFF)
            b[i + 2] = UInt8((v >> 16) & 0xFF)
            b[i + 3] = UInt8((v >> 24) & 0xFF)
        }
        func putU16(_ v: UInt16, _ i: Int) {
            b[i] = UInt8(v & 0xFF)
            b[i + 1] = UInt8((v >> 8) & 0xFF)
        }

        putU32(tMs, 0)
        putU32(weightG.bitPattern, 4)
        putU32(flowGps.bitPattern, 8)
        b[12] = state.rawValue
        var flags: UInt8 = 0
        if scaleConnected { flags |= 0x01 }
        if setpointReached { flags |= 0x02 }
        if state == .done { flags |= (endReason.rawValue & 0x07) << 2 }
        if awaitingPaddleReturn { flags |= 0x20 }
        b[13] = flags
        putU16(UInt16((setpointG * 100).rounded()), 14)
        return Data(b)
    }
}
