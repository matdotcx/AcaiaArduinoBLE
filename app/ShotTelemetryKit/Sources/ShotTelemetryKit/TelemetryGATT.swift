import CoreBluetooth

/// BLE identifiers for the ShotStopper peripheral. Must match the firmware
/// (`examples/shotStopper/shotStopper.ino`) — see `docs/GATT_DESIGN.md`.
///
/// IMPORTANT — the firmware declares its UUIDs as ArduinoBLE strings *with a
/// "0x" prefix*, e.g. `BLEService("0x0FFE")`, `BLECharacteristic("0xFF25", …)`.
/// ArduinoBLE's `BLEUuid` parser reads hex pairs from the END of the string and
/// treats the leftover "0x" as a third byte (0x00), which promotes the value to
/// a 128-bit UUID. So the device does NOT expose the Bluetooth-SIG 16-bit UUID
/// `0000FF25-0000-1000-8000-00805F9B34FB` that `CBUUID(string: "FF25")` builds —
/// it exposes `00000000-0000-0000-0000-00000000FF25`. We build CBUUIDs in that
/// exact form so scanning/discovery match the device (and the existing companion
/// app, which uses the same UUIDs). Do NOT "fix" the firmware strings to the
/// clean form — that would change every UUID and break the companion app.
public enum TelemetryGATT {
    /// The firmware's actual 128-bit UUID for a given 16-bit code (see note above).
    static func uuid(_ code: String) -> CBUUID {
        CBUUID(string: "00000000-0000-0000-0000-00000000" + code)
    }

    /// Primary service (`shotStopperService`, firmware `"0x0FFE"`).
    public static let service = uuid("0FFE")

    /// Live telemetry — 16-byte notify frame.
    public static let telemetry = uuid("FF25")

    /// Short human-readable firmware log lines (notify) — shown in the app's machine
    /// log so the firmware's event timeline is visible without a USB serial cable.
    public static let debugLog = uuid("FF26")

    // Configuration / control characteristics (all on the same service).
    public static let enabled = uuid("FF10")           // byte, write|read
    public static let setpoint = uuid("FF11")          // goal weight (g), byte, write|read
    public static let reedSwitch = uuid("FF12")        // byte, write|read
    public static let momentary = uuid("FF13")         // byte, write|read
    public static let autoTare = uuid("FF14")          // byte, write|read
    public static let minShotDuration = uuid("FF15")   // byte (s), write|read
    public static let maxShotDuration = uuid("FF16")   // byte (s), write|read
    public static let dripDelay = uuid("FF17")         // byte (s), write|read
    public static let firmwareVersion = uuid("FF18")   // byte, read
    public static let scaleStatus = uuid("FF19")       // byte, notify
    public static let shotStatus = uuid("FF20")        // byte, notify
    public static let otaModeRequested = uuid("FF21")  // byte, write|read
    public static let wifiSSID = uuid("FF22")          // string (≤32), write|read
    public static let wifiPassword = uuid("FF23")      // string (≤32), write
    public static let wifiIP = uuid("FF24")            // string (≤16), read|notify

    /// Characteristics whose values the client reads on connect.
    static let readableConfig: [CBUUID] = [
        enabled, setpoint, reedSwitch, momentary, autoTare,
        minShotDuration, maxShotDuration, dripDelay, firmwareVersion,
        otaModeRequested, wifiSSID, wifiIP,
    ]

    /// Characteristics the client subscribes to for notifications. `scaleStatus`
    /// and `shotStatus` are intentionally omitted: the telemetry frame already
    /// carries scale-connected + shot state, so subscribing to them produced
    /// notifications the client only dropped.
    static let notifying: [CBUUID] = [telemetry, debugLog, wifiIP]
}
