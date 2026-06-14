import SwiftUI
import SwiftData
import ShotTelemetryKit

/// Create or edit a recipe: name, identity (color + icon), and brew parameters.
struct RecipeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let existing: Preset?
    let defaults: DeviceSettings

    @State private var name = ""
    @State private var colorIndex = 0
    @State private var icon = DS.recipeIcons[0]
    @State private var goalWeight = 36
    @State private var autoTare = true
    @State private var dripDelay = 3
    @State private var loaded = false

    private var style: RecipeStyle { DS.recipeStyle(colorIndex: colorIndex, icon: icon) }

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    preview
                    section("NAME") {
                        TextField("Recipe name", text: $name)
                            .font(.system(size: 16, weight: .semibold))
                            .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                    section("COLOR") {
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(0..<DS.recipeColorPairs.count, id: \.self) { i in
                                Circle().fill(DS.recipeColor(i)).frame(width: 34, height: 34)
                                    .overlay(Circle().strokeBorder(DS.ink, lineWidth: colorIndex == i ? 3 : 0))
                                    .padding(2)
                                    .onTapGesture { colorIndex = i }
                            }
                        }
                        .padding(16)
                    }
                    section("ICON") {
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(DS.recipeIcons, id: \.self) { ic in
                                Image(systemName: ic).font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(icon == ic ? .white : DS.inkSecondary)
                                    .frame(width: 40, height: 40)
                                    .background(icon == ic ? style.solid : DS.ink.opacity(0.06),
                                               in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .onTapGesture { icon = ic }
                            }
                        }
                        .padding(16)
                    }
                    section("BREW") {
                        VStack(spacing: 0) {
                            paramRow("Target weight") {
                                stepper(goalWeight, "g", dec: { goalWeight = max(0, goalWeight - 1) }, inc: { goalWeight = min(100, goalWeight + 1) })
                            }
                            divider
                            HStack {
                                Text("Auto-tare").font(.system(size: 15, weight: .medium)).foregroundStyle(DS.ink)
                                Spacer()
                                Toggle("", isOn: $autoTare).labelsHidden().tint(DS.orange)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            divider
                            paramRow("Drip delay") {
                                stepper(dripDelay, "s", dec: { dripDelay = max(0, dripDelay - 1) }, inc: { dripDelay = min(30, dripDelay + 1) })
                            }
                        }
                    }
                    if existing != nil {
                        Button("Delete recipe", role: .destructive) { delete() }
                            .buttonStyle(DSPillStyle(kind: .outlined, fullWidth: true))
                            .tint(DS.orange)
                    }
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.vertical, DS.Space.l)
            }
            .background(DS.canvas)
            .navigationTitle(existing == nil ? "New recipe" : "Edit recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty).bold()
                }
            }
            .tint(DS.orange)
            .onAppear(perform: load)
        }
    }

    private var preview: some View {
        HStack(spacing: 12) {
            RecipeTokenChip(style: style, size: 44)
            RecipeTag(name: name.isEmpty ? "Recipe" : name, style: style)
            Spacer()
        }
        .padding(.top, 4)
    }

    private func section<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DSMonoLabel(label, color: DS.inkMuted)
            DSCard { content() }
        }
    }

    private func paramRow<T: View>(_ label: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack {
            Text(label).font(.system(size: 15, weight: .medium)).foregroundStyle(DS.ink)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func stepper(_ value: Int, _ unit: String, dec: @escaping () -> Void, inc: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: dec) { Image(systemName: "minus").font(.system(size: 14, weight: .bold)).foregroundStyle(DS.ink).frame(width: 38, height: 32) }
            Text("\(value) \(unit)").font(DS.numeral(15, .semibold)).monospacedDigit().foregroundStyle(DS.ink).frame(minWidth: 46)
            Button(action: inc) { Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(.white).frame(width: 38, height: 32).background(DS.orange) }
        }
        .background(DS.ink.opacity(0.05)).clipShape(Capsule())
        .overlay(Capsule().strokeBorder(DS.hairline, lineWidth: 1))
    }

    private var divider: some View { Rectangle().fill(DS.hairline).frame(height: 1).padding(.leading, 16) }

    private func load() {
        guard !loaded else { return }; loaded = true
        if let e = existing {
            name = e.name; colorIndex = e.colorIndex; icon = e.iconName
            goalWeight = e.goalWeightG; autoTare = e.autoTare; dripDelay = e.dripDelayS
        } else {
            goalWeight = Int(defaults.goalWeightG); autoTare = defaults.autoTare; dripDelay = Int(defaults.dripDelayS)
            colorIndex = Int.random(in: 0..<DS.recipeColorPairs.count)
            icon = DS.recipeIcons[colorIndex % DS.recipeIcons.count]
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let e = existing {
            e.name = trimmed; e.colorIndex = colorIndex; e.iconName = icon
            e.goalWeightG = goalWeight; e.autoTare = autoTare; e.dripDelayS = dripDelay
        } else {
            context.insert(Preset(name: trimmed, createdAt: .now, goalWeightG: goalWeight,
                                  autoTare: autoTare, minShotDurationS: Int(defaults.minShotDurationS),
                                  maxShotDurationS: Int(defaults.maxShotDurationS), dripDelayS: dripDelay,
                                  colorIndex: colorIndex, iconName: icon))
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        if let e = existing { context.delete(e); try? context.save() }
        dismiss()
    }
}
