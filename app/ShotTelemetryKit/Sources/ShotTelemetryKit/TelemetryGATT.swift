import CoreBluetooth

/// BLE identifiers for the ShotStopper peripheral. Must match the firmware
/// (`examples/shotStopper/shotStopper.ino`) — see `docs/GATT_DESIGN.md`.
///
/// The firmware uses Bluetooth-SIG 16-bit UUIDs; `CBUUID(string:)` accepts the
/// 4-hex-digit short form and expands it against the SIG base UUID.
public enum TelemetryGATT {
    /// Primary service (`shotStopperService`, `0x0FFE`).
    public static let service = CBUUID(string: "0FFE")

    /// Live telemetry — 16-byte notify frame.
    public static let telemetry = CBUUID(string: "FF25")

    // Configuration / control characteristics (all on the same service).
    public static let enabled = CBUUID(string: "FF10")           // byte, write|read
    public static let setpoint = CBUUID(string: "FF11")          // goal weight (g), byte, write|read
    public static let reedSwitch = CBUUID(string: "FF12")        // byte, write|read
    public static let momentary = CBUUID(string: "FF13")         // byte, write|read
    public static let autoTare = CBUUID(string: "FF14")          // byte, write|read
    public static let minShotDuration = CBUUID(string: "FF15")   // byte (s), write|read
    public static let maxShotDuration = CBUUID(string: "FF16")   // byte (s), write|read
    public static let dripDelay = CBUUID(string: "FF17")         // byte (s), write|read
    public static let firmwareVersion = CBUUID(string: "FF18")   // byte, read
    public static let scaleStatus = CBUUID(string: "FF19")       // byte, notify
    public static let shotStatus = CBUUID(string: "FF20")        // byte, notify
    public static let otaModeRequested = CBUUID(string: "FF21")  // byte, write|read
    public static let wifiSSID = CBUUID(string: "FF22")          // string (≤32), write|read
    public static let wifiPassword = CBUUID(string: "FF23")      // string (≤32), write
    public static let wifiIP = CBUUID(string: "FF24")            // string (≤16), read|notify

    /// Characteristics whose values the client reads on connect.
    static let readableConfig: [CBUUID] = [
        enabled, setpoint, reedSwitch, momentary, autoTare,
        minShotDuration, maxShotDuration, dripDelay, firmwareVersion,
        otaModeRequested, wifiSSID, wifiIP,
    ]

    /// Characteristics the client subscribes to for notifications.
    static let notifying: [CBUUID] = [telemetry, scaleStatus, shotStatus, wifiIP]
}
