import CoreBluetooth

/// BLE identifiers for the ShotStopper peripheral. Must match the firmware
/// (`examples/shotStopper/shotStopper.ino`) — see `docs/GATT_DESIGN.md`.
///
/// The firmware uses Bluetooth-SIG 16-bit UUIDs; `CBUUID(string:)` accepts the
/// 4-hex-digit short form and expands it against the SIG base UUID.
public enum TelemetryGATT {
    /// Primary service (`shotStopperService`, `0x0FFE`).
    public static let service = CBUUID(string: "0FFE")

    /// Live telemetry — 16-byte notify frame. The only characteristic this
    /// read-only app subscribes to.
    public static let telemetry = CBUUID(string: "FF25")

    // Other characteristics on the same service, for reference / future use.
    public static let setpoint = CBUUID(string: "FF11")          // goal weight (g), write|read
    public static let scaleStatus = CBUUID(string: "FF19")       // notify
    public static let shotStatus = CBUUID(string: "FF20")        // notify
    public static let firmwareVersion = CBUUID(string: "FF18")   // read
}
