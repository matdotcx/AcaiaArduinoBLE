import SwiftUI
import SwiftData
import ShotTelemetryKit

/// Machine configuration over BLE: connection, recipes, brew settings, OTA.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Preset.name) private var presets: [Preset]

    @State private var showEditor = false
    @State private var editorPreset: Preset?

    private var client: ShotStopperClient { model.client }
    private var s: DeviceSettings { client.settings }
    private var interactive: Bool {
#if targetEnvironment(simulator)
        true
#else
        client.isConnected
#endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    Text("Settings").font(DS.title(32)).foregroundStyle(DS.ink).padding(.top, DS.Space.s)
                    connectionCard
                    recipesSection
                    brewSection
                    deviceSection
                }
                .padding(.horizontal, DS.Space.xl).padding(.bottom, DS.Space.xl)
            }
            .background(DS.canvas)
            .navigationBarHidden(true)
            .sheet(isPresented: $showEditor) {
                RecipeEditorView(existing: editorPreset, defaults: s)
            }
            .onAppear {
#if DEBUG
#if targetEnvironment(simulator)
                if presets.isEmpty { seedSamplePresets() }
#endif
#endif
            }
        }
        .tint(DS.orange)
    }

    // MARK: Connection

    private var connectionCard: some View {
        DSCard {
            HStack(spacing: 12) {
                Circle().fill(client.isConnected ? DS.green : DS.idle).frame(width: 11, height: 11)
                VStack(alignment: .leading, spacing: 3) {
                    Text(client.isConnected ? (client.deviceName ?? "ShotStopper") : "ShotStopper")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(DS.ink)
                    Text(client.isConnected
                         ? "Reading data from the connected scale · firmware v\(s.firmwareVersion)"
                         : "Not connected · bring your phone near the machine")
                        .font(DS.mono(10)).foregroundStyle(DS.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                badge(client.isConnected ? "CONNECTED" : "OFFLINE", color: client.isConnected ? DS.green : DS.idle)
            }
            .padding(16)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        DSMonoLabel(text, size: 8.5, color: color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }

    // MARK: Recipes

    private var recipesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSMonoLabel("RECIPES", color: DS.inkMuted)
            DSCard {
                VStack(spacing: 0) {
                    if presets.isEmpty {
                        emptyRecipes
                    } else {
                        ForEach(Array(presets.enumerated()), id: \.element.id) { _, p in
                            recipeRow(p)
                            rowDivider
                        }
                        Button { editorPreset = nil; showEditor = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                                Text("Save current as recipe…").font(.system(size: 15, weight: .semibold))
                                Spacer()
                            }
                            .foregroundStyle(DS.orange)
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!interactive)
                    }
                }
            }
        }
    }

    private func recipeRow(_ p: Preset) -> some View {
        HStack(spacing: 10) {
            Button { model.applyRecipe(p) } label: {
                HStack(spacing: 12) {
                    RecipeTokenChip(style: DS.recipeStyle(colorIndex: p.colorIndex, icon: p.iconName), size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.system(size: 15, weight: .bold)).foregroundStyle(DS.ink)
                        Text("\(p.goalWeightG) g · \(p.dripDelayS) s drip" + (p.autoTare ? " · auto-tare" : ""))
                            .font(DS.mono(10)).foregroundStyle(DS.inkMuted)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!interactive)

            if model.activeRecipeID == p.id { badge("APPLIED", color: DS.green) }

            Button { editorPreset = p; showEditor = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.inkFaint).frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var emptyRecipes: some View {
        VStack(spacing: 10) {
            Image(systemName: "cup.and.saucer").font(.system(size: 26, weight: .light)).foregroundStyle(DS.inkFaint)
            Text("No recipes yet").font(.system(size: 16, weight: .bold)).foregroundStyle(DS.inkSecondary)
            Text("Dial in a shot you like, then save it as a recipe to apply it again later.")
                .font(.system(size: 13)).foregroundStyle(DS.inkMuted).multilineTextAlignment(.center)
                .frame(maxWidth: 240)
            Button("Save current dial-in") { editorPreset = nil; showEditor = true }
                .buttonStyle(DSPillStyle(kind: .orange)).padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28).padding(.horizontal, 16)
    }

    // MARK: Brew

    private var brewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSMonoLabel("BREW", color: DS.inkMuted)
            DSCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("Target weight").font(.system(size: 15, weight: .medium)).foregroundStyle(DS.ink)
                        Spacer()
                        stepper(value: Int(s.goalWeightG), unit: "g",
                                dec: { client.setGoalWeight(UInt8(max(0, Int(s.goalWeightG) - 1))); model.clearActiveRecipe() },
                                inc: { client.setGoalWeight(UInt8(min(100, Int(s.goalWeightG) + 1))); model.clearActiveRecipe() })
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    rowDivider
                    toggleRow("Brew by weight", isOn: boolBind(\.enabled, set: client.setEnabled))
                    rowDivider
                    toggleRow("Auto-tare", isOn: boolBind(\.autoTare, set: client.setAutoTare))
                }
            }
            .disabled(!interactive)
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(DS.ink) }
            .tint(DS.orange).padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func stepper(value: Int, unit: String, dec: @escaping () -> Void, inc: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text("\(value) \(unit)").font(DS.numeral(16, .bold)).monospacedDigit().foregroundStyle(DS.ink)
            HStack(spacing: 0) {
                Button(action: dec) { Image(systemName: "minus").font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.inkSecondary).frame(width: 44, height: 34) }
                Rectangle().fill(DS.hairline).frame(width: 1, height: 22)
                Button(action: inc) { Image(systemName: "plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.orange).frame(width: 44, height: 34) }
            }
            .background(DS.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
        }
    }

    // MARK: Device / OTA

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSMonoLabel("DEVICE", color: DS.inkMuted)
            DSCard {
                NavigationLink { OTAView() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.up.circle").font(.system(size: 18)).foregroundStyle(DS.ink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Firmware OTA").font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
                            Text("Current v\(s.firmwareVersion)").font(DS.mono(10)).foregroundStyle(DS.inkMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.inkFaint)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rowDivider: some View { Rectangle().fill(DS.hairline).frame(height: 1).padding(.leading, 16) }

    private func boolBind(_ kp: KeyPath<DeviceSettings, Bool>, set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { client.settings[keyPath: kp] }, set: { set($0); model.clearActiveRecipe() })
    }

#if DEBUG
    private func seedSamplePresets() {
        let samples: [(String, Int, Bool, Int)] = [
            ("House Espresso", 36, true, 3), ("Ethiopia Light", 40, true, 4), ("Ristretto", 22, false, 2),
        ]
        for (name, weight, tare, drip) in samples {
            context.insert(Preset(name: name, createdAt: .now, goalWeightG: weight, autoTare: tare,
                                  minShotDurationS: 5, maxShotDurationS: 50, dripDelayS: drip,
                                  colorIndex: DS.styleIndex(forName: name), iconName: DS.defaultIcon(forName: name)))
        }
        try? context.save()
    }
#endif
}
