import SwiftUI
import SwiftData
import ShotTelemetryKit

/// A saved shot: chart, flow, coaching, dial-in log, summary, export.
struct ShotDetailView: View {
    let shot: Shot
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var csvURL: URL?
    @State private var jsonURL: URL?
    @State private var notesDraft = ""
    @State private var confirmingDelete = false

    private var exportSamples: [ShotExport.Sample] { ShotExport(shot).samples }

    private var samples: [ChartSample] {
        exportSamples.enumerated().map { ChartSample(id: $0.offset, t: Double($0.element.tMs) / 1000, w: Double($0.element.weightG)) }
    }

    private var flowPoints: [FlowPoint] {
        ShotAnalyzer.flowCurve(exportSamples).enumerated().map { FlowPoint(id: $0.offset, t: $0.element.t, f: $0.element.f) }
    }

    private var analysis: (ShotMetrics, ExtractionAdvice) {
        ShotAnalyzer.analyse(exportSamples, doseG: shot.doseG > 0 ? Double(shot.doseG) : nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    header
                    ExtractionChart(samples: samples, target: Double(shot.setpointG), state: .done, showLeadingDot: false)
                        .frame(height: 220)
                    flowSection
                    coachingCard
                    dialInCard
                    summaryCard
                    exportButtons
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.s)
                .padding(.bottom, DS.Space.xl)
            }
            backBar
        }
        .background(DS.canvas)
        .navigationBarHidden(true)
        .task {
            generateExports()
            notesDraft = shot.notes
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shot detail").font(DS.title(28)).foregroundStyle(DS.ink)
            HStack(spacing: 6) {
                let tag = shot.statusTag
                Circle().fill(tag.color).frame(width: 6, height: 6)
                DSMonoLabel(shot.startedAt.formatted(.dateTime.month().day()).uppercased()
                            + " · " + shot.startedAt.formatted(.dateTime.hour().minute())
                            + " · " + tag.text,
                            size: 10, color: tag.color)
            }
        }
        .padding(.top, DS.Space.s)
    }

    // MARK: Flow

    @ViewBuilder private var flowSection: some View {
        if flowPoints.contains(where: { $0.f > 0 }) {
            VStack(alignment: .leading, spacing: 8) {
                DSMonoLabel("FLOW RATE · G/S", color: DS.inkMuted)
                FlowChart(points: flowPoints)
                    .frame(height: 110)
            }
        }
    }

    // MARK: Coaching

    private var coachingCard: some View {
        let advice = analysis.1
        return DSCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: verdictIcon(advice.verdict))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(verdictColor(advice.verdict))
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(advice.title).font(.system(size: 17, weight: .bold)).foregroundStyle(DS.ink)
                        Text(advice.summary).font(DS.mono(10)).foregroundStyle(DS.inkMuted)
                    }
                }
                if !advice.tips.isEmpty {
                    Rectangle().fill(DS.hairline).frame(height: 1)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(advice.tips.enumerated()), id: \.offset) { _, tip in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 12)).foregroundStyle(verdictColor(advice.verdict).opacity(0.7))
                                    .padding(.top, 2)
                                Text(tip).font(.system(size: 13)).foregroundStyle(DS.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func verdictColor(_ v: ExtractionVerdict) -> Color {
        switch v {
        case .ideal: return DS.green
        case .fast, .slow, .uneven: return DS.orange
        case .insufficientData: return DS.idle
        }
    }
    private func verdictIcon(_ v: ExtractionVerdict) -> String {
        switch v {
        case .ideal: return "checkmark.seal.fill"
        case .fast: return "hare.fill"
        case .slow: return "tortoise.fill"
        case .uneven: return "waveform.path.ecg"
        case .insufficientData: return "questionmark.circle"
        }
    }

    // MARK: Dial-in log

    private var dialInCard: some View {
        DSCard {
            VStack(spacing: 0) {
                summaryRow("Dose (grind)") {
                    HStack(spacing: 12) {
                        Text(shot.doseG > 0 ? String(format: "%.1f g", shot.doseG) : "—")
                            .font(DS.numeral(15, .semibold)).monospacedDigit()
                            .foregroundStyle(shot.doseG > 0 ? DS.ink : DS.disabledNum)
                        miniStepper(dec: { setDose(Double(shot.doseG) - 0.5) },
                                    inc: { setDose(Double(shot.doseG) + 0.5) })
                    }
                }
                rowDivider
                summaryRow("Brew ratio") {
                    value(shot.brewRatio.map { String(format: "1:%.1f", $0) } ?? "—")
                }
                rowDivider
                summaryRow("Taste") { stars }
                rowDivider
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes").font(.system(size: 14)).foregroundStyle(DS.inkMuted)
                    TextField("Tasting notes, what you changed…", text: $notesDraft, axis: .vertical)
                        .font(.system(size: 14)).foregroundStyle(DS.ink)
                        .lineLimit(2...5)
                        .onChange(of: notesDraft) { _, new in shot.notes = new; save() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
    }

    private var stars: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= shot.ratingStars ? "star.fill" : "star")
                    .font(.system(size: 16))
                    .foregroundStyle(i <= shot.ratingStars ? DS.orange : DS.inkFaint)
                    .onTapGesture {
                        shot.ratingStars = (shot.ratingStars == i ? 0 : i) // tap same star to clear
                        save()
                    }
            }
        }
    }

    private func miniStepper(dec: @escaping () -> Void, inc: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: dec) { Image(systemName: "minus").font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.inkSecondary).frame(width: 38, height: 30) }
            Rectangle().fill(DS.hairline).frame(width: 1, height: 18)
            Button(action: inc) { Image(systemName: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.orange).frame(width: 38, height: 30) }
        }
        .background(DS.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
    }

    private func setDose(_ g: Double) {
        shot.doseG = Float(max(0, min(40, g)))
        save()
    }

    private func save() { context.saveLogging() }

    // MARK: Summary / metrics

    private var summaryCard: some View {
        let m = analysis.0
        return DSCard {
            VStack(spacing: 0) {
                if let recipe = shot.presetName {
                    summaryRow("Recipe") {
                        HStack(spacing: 8) {
                            RecipeTokenChip(style: DS.recipeStyle(colorIndex: shot.recipeColorIndex, icon: shot.recipeIcon, name: recipe), size: 20)
                            Text(recipe).font(.system(size: 15, weight: .bold)).foregroundStyle(DS.ink)
                        }
                    }
                    rowDivider
                }
                summaryRow("Final weight") { value(String(format: "%.1f g", shot.finalWeightG)) }
                rowDivider
                summaryRow("Peak weight") { value(String(format: "%.1f g", shot.peakWeightG)) }
                rowDivider
                summaryRow("Duration") { value(String(format: "%.1f s", shot.durationS)) }
                rowDivider
                summaryRow("Peak flow") { value(String(format: "%.1f g/s", m.peakFlowGps)) }
                rowDivider
                summaryRow("Avg flow") { value(String(format: "%.1f g/s", m.avgFlowGps)) }
                if let ttfd = m.timeToFirstDropS {
                    rowDivider
                    summaryRow("Time to first drop") { value(String(format: "%.1f s", ttfd)) }
                }
                rowDivider
                summaryRow("Samples") { value("\(samples.count)") }
            }
        }
    }

    private func summaryRow<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(DS.inkMuted)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func value(_ s: String) -> some View {
        Text(s).font(DS.numeral(15, .semibold)).monospacedDigit().foregroundStyle(DS.ink)
    }

    private var rowDivider: some View { Rectangle().fill(DS.hairline).frame(height: 1).padding(.leading, 16) }

    private var exportButtons: some View {
        HStack(spacing: 12) {
            if let csvURL {
                ShareLink(item: csvURL) { Label("Export CSV", systemImage: "square.and.arrow.up") }
                    .buttonStyle(DSPillStyle(kind: .orange, fullWidth: true))
            }
            if let jsonURL {
                ShareLink(item: jsonURL) { Text("Export JSON") }
                    .buttonStyle(DSPillStyle(kind: .outlined, fullWidth: true))
            }
        }
    }

    private var backBar: some View {
        HStack {
            Button { dismiss() } label: {
                Label("Back", systemImage: "chevron.left").font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(DSPillStyle(kind: .outlined))
            Spacer()
            Button(role: .destructive) { confirmingDelete = true } label: {
                Image(systemName: "trash").font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(DSPillStyle(kind: .outlined))
            .tint(DS.orange)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.m)
        .background(DS.canvas)
        .confirmationDialog("Delete this shot?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete shot", role: .destructive) { deleteShot() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the shot and its curve from history. This can't be undone.")
        }
    }

    private func deleteShot() {
        context.delete(shot)
        context.saveLogging()
        dismiss()
    }

    private func generateExports() {
        let export = ShotExport(shot)
        let stem = ShotExporter.suggestedName(export)
        let dir = FileManager.default.temporaryDirectory
        let csv = dir.appendingPathComponent("\(stem).csv")
        if (try? Data(ShotExporter.csv(export).utf8).write(to: csv)) != nil { csvURL = csv }
        let json = dir.appendingPathComponent("\(stem).json")
        if let data = try? ShotExporter.json(export), (try? data.write(to: json)) != nil { jsonURL = json }
    }
}
