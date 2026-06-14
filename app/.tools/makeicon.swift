import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

// Renders a 1024x1024 app icon: a ShotStopper extraction curve (brand orange) rising
// over a cream background, with the dashed "target" line that the app's chart uses.
let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("ctx")
}

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

// Background: warm cream (#e9e7e0)
ctx.setFillColor(color(0.913, 0.905, 0.878))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Dashed "target" line (matches the chart's setpoint rule)
ctx.setStrokeColor(color(0.25, 0.24, 0.22, 0.55))
ctx.setLineWidth(12)
ctx.setLineCap(.round)
ctx.setLineDash(phase: 0, lengths: [34, 28])
ctx.move(to: CGPoint(x: 130, y: 742))
ctx.addLine(to: CGPoint(x: 894, y: 742))
ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [])

// Extraction curve (brand orange #e84b29), rising S-curve
ctx.setStrokeColor(color(0.909, 0.294, 0.161))
ctx.setLineWidth(60)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
let path = CGMutablePath()
path.move(to: CGPoint(x: 150, y: 250))
path.addCurve(to: CGPoint(x: 870, y: 800),
              control1: CGPoint(x: 440, y: 250),
              control2: CGPoint(x: 540, y: 800))
ctx.addPath(path)
ctx.strokePath()

// Current-weight dot at the curve's end
ctx.setFillColor(color(0.909, 0.294, 0.161))
ctx.fillEllipse(in: CGRect(x: 870 - 50, y: 800 - 50, width: 100, height: 100))

guard let img = ctx.makeImage() else { fatalError("img") }
let out = URL(fileURLWithPath: CommandLine.arguments[1])
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("dest")
}
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")
