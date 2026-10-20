import AppKit
import Foundation

enum IconError: Error {
    case renderingFailed
    case conversionFailed
}

@MainActor
func drawMark(colored: Bool) {
    let left = NSBezierPath()
    left.move(to: NSPoint(x: 432, y: 688))
    left.line(to: NSPoint(x: 272, y: 528))
    left.line(to: NSPoint(x: 432, y: 368))
    let right = NSBezierPath()
    right.move(to: NSPoint(x: 592, y: 688))
    right.line(to: NSPoint(x: 752, y: 528))
    right.line(to: NSPoint(x: 592, y: 368))
    for (index, path) in [left, right].enumerated() {
        path.lineWidth = 72
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        let color = colored && index == 0
            ? NSColor(srgbRed: 0.75, green: 0.68, blue: 1, alpha: 1)
            : NSColor.white
        NSGraphicsContext.saveGraphicsState()
        if colored {
            let glow = NSShadow()
            glow.shadowColor = color.withAlphaComponent(0.28)
            glow.shadowBlurRadius = 26
            glow.shadowOffset = .zero
            glow.set()
        }
        color.setStroke()
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    let star = NSBezierPath()
    star.move(to: NSPoint(x: 512, y: 870))
    star.curve(to: NSPoint(x: 576, y: 806), controlPoint1: NSPoint(x: 522, y: 820),
               controlPoint2: NSPoint(x: 526, y: 816))
    star.curve(to: NSPoint(x: 512, y: 742), controlPoint1: NSPoint(x: 526, y: 796),
               controlPoint2: NSPoint(x: 522, y: 792))
    star.curve(to: NSPoint(x: 448, y: 806), controlPoint1: NSPoint(x: 502, y: 792),
               controlPoint2: NSPoint(x: 498, y: 796))
    star.curve(to: NSPoint(x: 512, y: 870), controlPoint1: NSPoint(x: 498, y: 816),
               controlPoint2: NSPoint(x: 502, y: 820))
    star.close()
    (colored ? NSColor(srgbRed: 0.7, green: 0.98, blue: 0.82, alpha: 1) : .white).setFill()
    star.fill()
}

@MainActor
func drawIcon() {
    let tile = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880),
                            xRadius: 200, yRadius: 200)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 20
    shadow.shadowOffset = NSSize(width: 0, height: -9)
    shadow.set()
    NSColor.black.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(srgbRed: 0.24, green: 0.21, blue: 0.36, alpha: 1),
        NSColor(srgbRed: 0.1, green: 0.1, blue: 0.16, alpha: 1),
        NSColor(srgbRed: 0.035, green: 0.045, blue: 0.075, alpha: 1)
    ])?.draw(in: tile, angle: -60)

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    let reflection = NSBezierPath()
    reflection.move(to: NSPoint(x: 90, y: 780))
    reflection.curve(to: NSPoint(x: 940, y: 890), controlPoint1: NSPoint(x: 340, y: 1010),
                     controlPoint2: NSPoint(x: 660, y: 790))
    reflection.lineWidth = 3
    NSColor.white.withAlphaComponent(0.08).setStroke()
    reflection.stroke()
    NSGraphicsContext.restoreGraphicsState()

    tile.lineWidth = 2
    NSColor.white.withAlphaComponent(0.2).setStroke()
    tile.stroke()
    drawMark(colored: true)
}

@MainActor
func writeIcon(pixels: Int, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw IconError.renderingFailed }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw IconError.renderingFailed }
    try data.write(to: url)
}

@MainActor
final class MarkView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.translateBy(x: -160, y: -248)
        drawMark(colored: false)
    }
}

@MainActor
func generateAssets() throws {
    let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for size in [16, 32, 128, 256, 512] {
        try writeIcon(pixels: size, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
        try writeIcon(pixels: size * 2, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
    }
    try writeIcon(pixels: 256, to: output.appendingPathComponent("logo.png"))
    let mark = MarkView(frame: NSRect(x: 0, y: 0, width: 704, height: 704))
    try mark.dataWithPDF(inside: mark.bounds).write(to: output.appendingPathComponent("LogoMark.pdf"))

    let conversion = Process()
    conversion.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    conversion.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
    try conversion.run()
    conversion.waitUntilExit()
    guard conversion.terminationStatus == 0 else { throw IconError.conversionFailed }
}

try MainActor.assumeIsolated { try generateAssets() }
