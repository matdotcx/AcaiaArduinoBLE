import SwiftUI
import Charts
import ShotTelemetryKit

// Swift Charts views for the ShotStopper visual system. Split out of DesignSystem.swift
// to keep each file under the 400-line quality bar; depends on the DS tokens there.

// MARK: - Extraction chart (the hero — Swift Charts)

struct ChartSample: Identifiable {
    let id: Int
    let t: Double   // seconds
    let w: Double   // grams
}

struct ExtractionChart: View {
    var samples: [ChartSample]
    var target: Double
    var state: BrewVisualState
    var showAxes: Bool = true
    var showLeadingDot: Bool = true
    var dimmed: Bool = false

    private var lineColor: Color { dimmed ? Color(rgb: 0x7A7A7E) : state.color }
    private var lineWidth: CGFloat { dimmed ? 2.6 : 3.4 }
    private var yMax: Double {
        max(target * 1.12, (samples.map(\.w).max() ?? target) * 1.06, 1)
    }

    @ChartContentBuilder private var marks: some ChartContent {
        if target > 0 {
            RuleMark(y: .value("Target", target))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 7]))
                .foregroundStyle(dimmed ? Color(rgb: 0x5A5A5E) : DS.targetLine)
        }
        ForEach(samples) { s in
            if !dimmed {
                AreaMark(x: .value("t", s.t), y: .value("w", s.w))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(
                        colors: [lineColor.opacity(0.20), lineColor.opacity(0)],
                        startPoint: .top, endPoint: .bottom))
            }
            LineMark(x: .value("t", s.t), y: .value("w", s.w))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .foregroundStyle(lineColor)
        }
        if showLeadingDot, state == .brewing, !dimmed, let last = samples.last {
            PointMark(x: .value("t", last.t), y: .value("w", last.w))
                .symbolSize(70)
                .foregroundStyle(lineColor)
        }
    }

    var body: some View {
        if showAxes {
            Chart { marks }
                .chartYScale(domain: 0...yMax)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(DS.gridline)
                        AxisValueLabel {
                            if let g = value.as(Double.self) {
                                Text("\(Int(g))").font(DS.mono(9)).foregroundStyle(DS.inkFaint)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisValueLabel {
                            if let s = value.as(Double.self) {
                                Text("\(Int(s)) s").font(DS.mono(9)).foregroundStyle(DS.inkFaint)
                            }
                        }
                    }
                }
        } else {
            Chart { marks }
                .chartYScale(domain: 0...yMax)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
        }
    }
}

extension ExtractionChart {
    /// Build chart samples from telemetry frames (live curve).
    static func samples(fromFrames frames: [TelemetryFrame]) -> [ChartSample] {
        frames.enumerated().map { ChartSample(id: $0.offset, t: $0.element.elapsed, w: Double($0.element.weightG)) }
    }
}

// MARK: - Flow-rate chart (g/s over time)

struct FlowPoint: Identifiable {
    let id: Int
    let t: Double   // seconds
    let f: Double   // g/s
}

/// Compact flow-rate curve in g/s, with its own axis. Shown beneath the weight
/// chart on Shot Detail. Flow is the derived cup-side rate (see ShotAnalyzer).
struct FlowChart: View {
    var points: [FlowPoint]
    var color: Color = DS.orange

    private var yMax: Double { max((points.map(\.f).max() ?? 1) * 1.15, 0.5) }

    var body: some View {
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("t", p.t), y: .value("flow", p.f))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.linearGradient(
                        colors: [color.opacity(0.18), color.opacity(0)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("t", p.t), y: .value("flow", p.f))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(color)
            }
        }
        .chartYScale(domain: 0...yMax)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(DS.gridline)
                AxisValueLabel {
                    if let g = value.as(Double.self) {
                        Text(String(format: "%.1f", g)).font(DS.mono(9)).foregroundStyle(DS.inkFaint)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let s = value.as(Double.self) {
                        Text("\(Int(s)) s").font(DS.mono(9)).foregroundStyle(DS.inkFaint)
                    }
                }
            }
        }
    }
}
