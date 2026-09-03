// Renders build/AppIcon.iconset — run via `swift Tools/MakeIcon.swift <output-iconset-dir>`.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let size = CGFloat(pixels)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { fatalError("could not allocate a \(pixels)px bitmap") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let inset = size * 0.055
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let squircle = NSBezierPath(roundedRect: rect,
                                xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(srgbRed: 1.00, green: 0.35, blue: 0.42, alpha: 1),
                        NSColor(srgbRed: 0.85, green: 0.13, blue: 0.26, alpha: 1)])?
        .draw(in: squircle, angle: -90)

    // Upload glyph: a tray with an arrow rising out of it.
    let white = NSColor.white
    white.setStroke()
    white.setFill()

    let stroke = size * 0.075
    let cx = size / 2

    let arrow = NSBezierPath()
    arrow.lineWidth = stroke
    arrow.lineCapStyle = .round
    arrow.move(to: NSPoint(x: cx, y: size * 0.34))
    arrow.line(to: NSPoint(x: cx, y: size * 0.70))
    arrow.stroke()

    let head = NSBezierPath()
    head.lineWidth = stroke
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.move(to: NSPoint(x: cx - size * 0.15, y: size * 0.555))
    head.line(to: NSPoint(x: cx, y: size * 0.705))
    head.line(to: NSPoint(x: cx + size * 0.15, y: size * 0.555))
    head.stroke()

    let tray = NSBezierPath()
    tray.lineWidth = stroke
    tray.lineCapStyle = .round
    tray.lineJoinStyle = .round
    tray.move(to: NSPoint(x: cx - size * 0.21, y: size * 0.40))
    tray.line(to: NSPoint(x: cx - size * 0.21, y: size * 0.265))
    tray.line(to: NSPoint(x: cx + size * 0.21, y: size * 0.265))
    tray.line(to: NSPoint(x: cx + size * 0.21, y: size * 0.40))
    tray.stroke()

    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("could not encode the \(pixels)px icon")
    }
    return png
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let suffix = scale == 1 ? "" : "@2x"
    let data = render(points * scale)
    try data.write(to: out.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
}
print("wrote \(out.path)")
