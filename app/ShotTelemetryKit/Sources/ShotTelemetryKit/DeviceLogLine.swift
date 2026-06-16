import Foundation

/// One firmware log line received over BLE (`0xFF26`) — the device's event timeline
/// (button, tare, latch, shot end) shown in the app's machine log.
public struct DeviceLogLine: Identifiable, Equatable, Sendable {
    public let id: Int
    public let at: Date
    public let text: String

    public init(id: Int, at: Date, text: String) {
        self.id = id
        self.at = at
        self.text = text
    }
}
