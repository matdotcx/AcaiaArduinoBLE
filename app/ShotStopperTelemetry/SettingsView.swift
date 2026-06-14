import SwiftUI
import ShotTelemetryKit

/// Read/write the ShotStopper's configuration over BLE. Changes are written
/// immediately. Controls are disabled until the device is connected.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    private var client: ShotStopperClient { model.client }
    private var s: DeviceSettings { client.settings }

    var body: some View {
        NavigationStack {
            Form {
                if !client.isConnected {
                    Section {
                        Label("Not connected", systemImage: "antenna.radiowaves.left.and.right.slash")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Brew") {
                    Stepper(value: bind(\.goalWeightG, set: client.setGoalWeight), in: 0...100) {
                        LabeledContent("Target weight", value: "\(s.goalWeightG) g")
                    }
                    Toggle("Brew by weight enabled", isOn: boolBind(\.enabled, set: client.setEnabled))
                    Toggle("Auto-tare", isOn: boolBind(\.autoTare, set: client.setAutoTare))
                }

                Section("Switch") {
                    Toggle("Momentary button", isOn: boolBind(\.momentary, set: client.setMomentary))
                    Toggle("Reed switch", isOn: boolBind(\.reedSwitch, set: client.setReedSwitch))
                }

                Section("Timing") {
                    Stepper(value: bind(\.minShotDurationS, set: client.setMinShotDuration), in: 0...60) {
                        LabeledContent("Min shot duration", value: "\(s.minShotDurationS) s")
                    }
                    Stepper(value: bind(\.maxShotDurationS, set: client.setMaxShotDuration), in: 0...120) {
                        LabeledContent("Max shot duration", value: "\(s.maxShotDurationS) s")
                    }
                    Stepper(value: bind(\.dripDelayS, set: client.setDripDelay), in: 0...30) {
                        LabeledContent("Drip delay", value: "\(s.dripDelayS) s")
                    }
                }

                Section("Firmware") {
                    LabeledContent("Version", value: "\(s.firmwareVersion)")
                    NavigationLink("Update firmware (OTA)") { OTAView() }
                }
            }
            .navigationTitle("Settings")
            .disabled(!interactive)
        }
    }

    /// On device, controls are live only when connected. In the Simulator (no BLE)
    /// they stay interactive so the screen can be previewed/demoed.
    private var interactive: Bool {
#if targetEnvironment(simulator)
        true
#else
        client.isConnected
#endif
    }

    // Custom bindings that read from settings and write through the client.
    private func bind(_ kp: KeyPath<DeviceSettings, UInt8>, set: @escaping (UInt8) -> Void) -> Binding<UInt8> {
        Binding(get: { client.settings[keyPath: kp] }, set: { set($0) })
    }
    private func boolBind(_ kp: KeyPath<DeviceSettings, Bool>, set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { client.settings[keyPath: kp] }, set: { set($0) })
    }
}
