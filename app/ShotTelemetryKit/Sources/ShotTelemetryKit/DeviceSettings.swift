import Foundation

/// The ShotStopper's configuration, mirrored from its BLE characteristics.
/// Populated as the client reads each characteristic on connect, and updated
/// locally when the app writes a change back.
public struct DeviceSettings: Sendable, Equatable {
    public var enabled: Bool = true
    /// Goal/target weight in grams (the setpoint the machine brews to).
    public var goalWeightG: UInt8 = 36
    public var momentary: Bool = false
    public var reedSwitch: Bool = false
    public var autoTare: Bool = false
    public var minShotDurationS: UInt8 = 0
    public var maxShotDurationS: UInt8 = 50
    public var dripDelayS: UInt8 = 3
    public var firmwareVersion: UInt8 = 0      // read-only
    public var otaRequested: Bool = false
    public var wifiSSID: String = ""
    public var wifiIP: String = ""             // read-only / notified

    public init() {}
}
