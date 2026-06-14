import SwiftUI
import SwiftData
import ShotTelemetryKit

/// Read/write the ShotStopper's configuration over BLE. Changes are written
/// immediately. Controls are disabled until the device is connected.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Preset.name) private var presets: [Preset]

    @State private var showingSave = false
    @State private var newPresetName = ""

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

                Section("Presets") {
                    ForEach(presets) { preset in
                        Button { apply(preset) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                Text("\(preset.goalWeightG) g · \(preset.dripDelayS) s drip"
                                     + (preset.autoTare ? " · auto-tare" : ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(.primary)
                    }
                    .onDelete(perform: deletePresets)

                    Button("Save current as preset…") { showingSave = true }
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
            .alert("Save preset", isPresented: $showingSave) {
                TextField("Name", text: $newPresetName)
                Button("Save") { savePreset() }.disabled(newPresetName.isEmpty)
                Button("Cancel", role: .cancel) { newPresetName = "" }
            } message: {
                Text("Saves the current target weight, timing and auto-tare under a name.")
            }
            .onAppear {
#if DEBUG
#if targetEnvironment(simulator)
                if presets.isEmpty { seedSamplePresets() }
#endif
#endif
            }
        }
    }

#if DEBUG
    private func seedSamplePresets() {
        let samples = [
            ("House Espresso", 36, true, 3),
            ("Ethiopia Light", 40, true, 4),
            ("Ristretto", 22, false, 2),
        ]
        for (name, weight, tare, drip) in samples {
            context.insert(Preset(name: name, createdAt: .now, goalWeightG: weight,
                                  autoTare: tare, minShotDurationS: 5, maxShotDurationS: 50, dripDelayS: drip))
        }
        try? context.save()
    }
#endif

    /// Write a preset's values to the device.
    private func apply(_ preset: Preset) {
        client.setGoalWeight(UInt8(clamping: preset.goalWeightG))
        client.setAutoTare(preset.autoTare)
        client.setMinShotDuration(UInt8(clamping: preset.minShotDurationS))
        client.setMaxShotDuration(UInt8(clamping: preset.maxShotDurationS))
        client.setDripDelay(UInt8(clamping: preset.dripDelayS))
    }

    private func savePreset() {
        let preset = Preset(
            name: newPresetName.trimmingCharacters(in: .whitespaces),
            createdAt: .now,
            goalWeightG: Int(s.goalWeightG),
            autoTare: s.autoTare,
            minShotDurationS: Int(s.minShotDurationS),
            maxShotDurationS: Int(s.maxShotDurationS),
            dripDelayS: Int(s.dripDelayS)
        )
        context.insert(preset)
        try? context.save()
        newPresetName = ""
    }

    private func deletePresets(_ offsets: IndexSet) {
        for index in offsets { context.delete(presets[index]) }
        try? context.save()
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
