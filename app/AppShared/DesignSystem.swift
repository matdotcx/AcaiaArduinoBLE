import SwiftUI
import Charts
import CoreText
import ShotTelemetryKit

// ShotStopper Visual System v1 — design tokens + reusable components.
// Fonts: the spec's Grotesque (Archivo) is now bundled as a variable font
// (AppShared/Archivo-Variable.ttf) and driven on its wght/wdth axes to hit the
// spec's exact weights + expanded width (font-stretch 110–120%). Space Mono is
// still substituted by SF Mono (DS.mono). If the font fails to load we fall back
// to SF Pro (.expanded) — same intent, never a crash.

// MARK: - Color helpers

extension Color {
    init(rgb: UInt) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: 1)
    }
}

#if os(watchOS)
// watchOS is always dark; no dynamic provider.
private func dyn(_ light: UInt, _ dark: UInt) -> Color { Color(rgb: dark) }
private func dynColor(_ light: Color, _ dark: Color) -> Color { dark }
#else
import UIKit
private func dyn(_ light: UInt, _ dark: UInt) -> Color {
    Color(uiColor: UIColor { tc in
        UIColor(Color(rgb: tc.userInterfaceStyle == .dark ? dark : light))
    })
}
private func dynColor(_ light: Color, _ dark: Color) -> Color {
    Color(uiColor: UIColor { tc in
        UIColor(tc.userInterfaceStyle == .dark ? dark : light)
    })
}
#endif

// MARK: - Tokens

enum DS {
    // Surfaces / ink
    static let canvas        = dyn(0xE9E7E0, 0x121110)
    static let surface       = dyn(0xFBFAF4, 0x1E1C18)
    static let surfaceRaised = dyn(0xFFFFFF, 0x26231E)
    static let ink           = dyn(0x111110, 0xF1EFE8)
    static let inkSecondary  = dyn(0x4A463F, 0xC2BCB0)
    static let inkMuted      = dyn(0x6E6A62, 0x918C82)
    static let inkFaint      = dyn(0xA6A299, 0x6E6A62)
    static let disabledNum   = dyn(0xC9C5BC, 0x4A463F)
    static let onInk         = dyn(0xFBFAF4, 0x121110) // text on an ink-filled pill

    // Brand & state
    static let orange = dyn(0xE84B29, 0xFB5A35)
    static let green  = dyn(0x1F6B4A, 0x43B585)
    static let idle   = dyn(0xA6A299, 0x8A8A8E)

    static let hairline = dynColor(Color(rgb: 0x111110).opacity(0.10),
                                    Color(rgb: 0xF1EFE8).opacity(0.12))
    static let gridline = dynColor(Color(rgb: 0x111110).opacity(0.07),
                                   Color(rgb: 0xF1EFE8).opacity(0.08))
    static let targetLine = dynColor(Color(rgb: 0x111110).opacity(0.42),
                                     Color(rgb: 0xF1EFE8).opacity(0.40))

    // Spacing scale (4-based)
    enum Space { static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24, xxl: CGFloat = 32 }
    // Radius
    enum R { static let card: CGFloat = 18, inner: CGFloat = 14, chip: CGFloat = 7 }

    // MARK: Fonts (Archivo variable for the Grotesque; SF Mono for the mono)
    // Width ~115 = the spec's expanded look; hero/title carry the spec's exact weights.
    static func hero(_ size: CGFloat) -> Font { Archivo.font(size, weight: 480, width: 116) }
    static func numeral(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { Archivo.font(size, weight: Archivo.wght(weight), width: 115) }
    static func title(_ size: CGFloat = 30) -> Font { Archivo.font(size, weight: 600, width: 110) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }
}

// MARK: - Archivo variable-font loader

/// Builds SwiftUI `Font`s from the bundled Archivo variable font, setting the
/// wght/wdth axes explicitly (the variable font's default instance is neither
/// the weight nor the expanded width the spec calls for). Tabular figures are
/// baked in so numerals stay column-aligned. Loaded straight from the bundle —
/// no `UIAppFonts` registration required.
fileprivate enum Archivo {
    static let wghtAxis = 0x77676874   // 'wght' (id 2003265652)
    static let wdthAxis = 0x77647468   // 'wdth' (id 2003072104)

    /// Base descriptor for the bundled variable font, resolved once.
    static let base: CTFontDescriptor? = {
        guard let url = Bundle.main.url(forResource: "Archivo-Variable", withExtension: "ttf"),
              let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descs.first else { return nil }
        return first
    }()

    /// Map a SwiftUI weight to a numeric value on the wght axis (100–900).
    static func wght(_ w: Font.Weight) -> CGFloat {
        if w == .ultraLight { return 100 }
        if w == .thin       { return 200 }
        if w == .light      { return 300 }
        if w == .regular    { return 400 }
        if w == .medium     { return 500 }
        if w == .semibold   { return 600 }
        if w == .bold       { return 700 }
        if w == .heavy      { return 800 }
        if w == .black      { return 900 }
        return 500
    }

    static func font(_ size: CGFloat, weight: CGFloat, width: CGFloat) -> Font {
        guard let base else {
            // Font missing from the bundle — keep the original SF substitution.
            return .system(size: size, weight: .regular).width(.expanded)
        }
        let variations: [NSNumber: NSNumber] = [
            NSNumber(value: wghtAxis): NSNumber(value: Double(weight)),
            NSNumber(value: wdthAxis): NSNumber(value: Double(width)),
        ]
        // Tabular figures: kNumberSpacingType (6) / kMonospacedNumbersSelector (0).
        let tnum: [CFString: Int] = [
            kCTFontFeatureTypeIdentifierKey: 6,
            kCTFontFeatureSelectorIdentifierKey: 0,
        ]
        let attrs: [CFString: Any] = [
            kCTFontVariationAttribute: variations,
            kCTFontFeatureSettingsAttribute: [tnum],
        ]
        let desc = CTFontDescriptorCreateCopyWithAttributes(base, attrs as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(desc, size, nil))
    }
}

// MARK: - Brew visual state

enum BrewVisualState {
    case idle, brewing, done
    var color: Color {
        switch self {
        case .idle:    return DS.idle
        case .brewing: return DS.orange
        case .done:    return DS.green
        }
    }
}

// MARK: - Recipe identity palette

struct RecipeStyle {
    let icon: String
    let solid: Color    // chip background / dot
    let tagText: Color  // tag label text
    var tagBackground: Color { solid.opacity(0.15) }
}

extension DS {
    /// Recipe color palette (light, dark). Indices 0–3 keep the handoff's
    /// House Espresso / Ethiopia Light / Ristretto / Decaf; the rest extend it.
    static let recipeColorPairs: [(UInt, UInt)] = [
        (0x7A4E2E, 0xC08A5E), // umber
        (0xC28A1E, 0xE0B24E), // amber
        (0xA32E3C, 0xE0788A), // garnet
        (0x44617F, 0x8AA6C2), // slate
        (0x2F7D6E, 0x5FC4B0), // teal
        (0x6B4FA3, 0xB39DE0), // plum
        (0xB5532A, 0xE8895E), // terracotta
        (0x3E6CA6, 0x7FA8DE), // blue
        (0x9A2F6E, 0xE08AC0), // magenta
        (0x5C6B2E, 0xAEC074), // olive
        (0x2C7A4B, 0x57C285), // forest
        (0x8A6310, 0xE6BE64), // ochre
    ]
    /// Recipe icon set (SF Symbols).
    static let recipeIcons: [String] = [
        "cup.and.saucer.fill", "leaf.fill", "drop.fill", "moon.fill",
        "flame.fill", "sparkles", "bolt.fill", "star.fill",
        "heart.fill", "mug.fill", "camera.macro", "circle.hexagongrid.fill",
    ]

    static func recipeColor(_ index: Int) -> Color {
        let n = recipeColorPairs.count
        let p = recipeColorPairs[((index % n) + n) % n]
        return dyn(p.0, p.1)
    }
    static func recipeStyle(colorIndex: Int, icon: String) -> RecipeStyle {
        let c = recipeColor(colorIndex)
        return RecipeStyle(icon: icon.isEmpty ? recipeIcons[0] : icon, solid: c, tagText: c)
    }

    /// Stable color index from a recipe name (fallback for shots that only carry a name).
    static func styleIndex(forName name: String) -> Int {
        let known = ["House Espresso": 0, "Ethiopia Light": 1, "Ristretto": 2, "Decaf": 3]
        if let i = known[name] { return i }
        return abs(name.hashValue) % recipeColorPairs.count
    }
    static func defaultIcon(forName name: String) -> String {
        let known = ["House Espresso": "cup.and.saucer.fill", "Ethiopia Light": "leaf.fill",
                     "Ristretto": "drop.fill", "Decaf": "moon.fill"]
        return known[name] ?? recipeIcons[styleIndex(forName: name) % recipeIcons.count]
    }
    static func recipeStyle(forName name: String) -> RecipeStyle {
        recipeStyle(colorIndex: styleIndex(forName: name), icon: defaultIcon(forName: name))
    }
    /// Resolve a style from optional stored fields, falling back to the name.
    static func recipeStyle(colorIndex: Int?, icon: String?, name: String?) -> RecipeStyle {
        if let ci = colorIndex { return recipeStyle(colorIndex: ci, icon: icon ?? recipeIcons[((ci % recipeIcons.count) + recipeIcons.count) % recipeIcons.count]) }
        if let name { return recipeStyle(forName: name) }
        return recipeStyle(colorIndex: 0, icon: recipeIcons[0])
    }
}

// MARK: - Components

/// A grouped card: surface fill, hairline border, card radius.
struct DSCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.R.card, style: .continuous).strokeBorder(DS.hairline, lineWidth: 1))
    }
}

/// Uppercase, tracked, mono micro-label.
struct DSMonoLabel: View {
    let text: String
    var size: CGFloat = 10
    var color: Color = DS.inkFaint
    init(_ text: String, size: CGFloat = 10, color: Color = DS.inkFaint) {
        self.text = text; self.size = size; self.color = color
    }
    var body: some View {
        Text(text.uppercased())
            .font(DS.mono(size, .medium))
            .tracking(1.5)
            .foregroundStyle(color)
    }
}

/// Solid square token chip with a white recipe glyph.
struct RecipeTokenChip: View {
    let style: RecipeStyle
    var size: CGFloat = 30
    var body: some View {
        RoundedRectangle(cornerRadius: max(6, size * 0.22), style: .continuous)
            .fill(style.solid)
            .frame(width: size, height: size)
            .overlay(Image(systemName: style.icon)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white))
    }
}

/// Capsule recipe tag (dot + name) or, when name is nil, an outlined "No recipe".
struct RecipeTag: View {
    let name: String?
    var style: RecipeStyle = DS.recipeStyle(colorIndex: 0, icon: DS.recipeIcons[0])
    var body: some View {
        if let name {
            HStack(spacing: 5) {
                Circle().fill(style.solid).frame(width: 6, height: 6)
                Text(name).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(style.tagText)
            }
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(style.tagBackground, in: Capsule())
        } else {
            Text("No recipe")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(DS.inkFaint)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .overlay(Capsule().strokeBorder(DS.hairline, lineWidth: 1))
        }
    }
}

/// Pill button styles (full capsule, consistent everywhere).
struct DSPillStyle: ButtonStyle {
    enum Kind { case orange, ink, green, outlined, recipe(Color) }
    var kind: Kind = .orange
    var fullWidth: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        let (bg, fg, bordered): (Color, Color, Bool) = {
            switch kind {
            case .orange:        return (DS.orange, .white, false)
            case .ink:           return (DS.ink, DS.onInk, false)
            case .green:         return (DS.green, .white, false)
            case .outlined:      return (.clear, DS.ink, true)
            case .recipe(let c): return (c, .white, false)
            }
        }()
        return configuration.label
            .font(.system(size: 15.5, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.vertical, 13).padding(.horizontal, 20)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(bg, in: Capsule())
            .overlay(Capsule().strokeBorder(bordered ? DS.hairline : .clear, lineWidth: 1.3))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

/// A small pulsing dot (REC / uploading). Respects Reduce Motion.
struct PulsingDot: View {
    var color: Color = DS.orange
    var size: CGFloat = 8
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
            .opacity(on ? 0.25 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

/// REC / DONE state pill for the Live status row.
struct StatusPill: View {
    let state: BrewVisualState
    var body: some View {
        switch state {
        case .brewing:
            HStack(spacing: 6) { PulsingDot(color: DS.orange, size: 7); Text("REC").font(DS.mono(11, .bold)).tracking(1.5).foregroundStyle(DS.orange) }
        case .done:
            HStack(spacing: 5) {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(DS.green)
                Text("DONE").font(DS.mono(11, .bold)).tracking(1.5).foregroundStyle(DS.green)
            }
        case .idle:
            EmptyView()
        }
    }
}

/// Progress-to-target pill bar.
struct TargetProgressBar: View {
    var fraction: Double
    var color: Color
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.ink.opacity(0.08))
                Capsule().fill(color)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

/// Tiny line sparkline for History rows.
struct Sparkline: View {
    var values: [Double]
    var color: Color
    var lineWidth: CGFloat = 2.4
    var body: some View {
        GeometryReader { geo in
            Path { p in
                guard values.count > 1, let mx = values.max(), mx > 0 else { return }
                let stepX = geo.size.width / CGFloat(values.count - 1)
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(x: CGFloat(i) * stepX, y: geo.size.height * (1 - CGFloat(v / mx) * 0.92) - 1)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

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
