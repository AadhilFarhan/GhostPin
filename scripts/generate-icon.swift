// Generates Assets/AppIcon.icns and README/site PNGs.
// Run: swift scripts/generate-icon.swift
import AppKit

let canvas: CGFloat = 1024

func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
    let result = NSImage(size: image.size)
    result.lockFocus()
    image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    color.set()
    NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
    result.unlockFocus()
    return result
}

func renderMaster() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Squircle background
    let margin: CGFloat = 100
    let bgRect = NSRect(x: margin, y: margin, width: canvas - 2 * margin, height: canvas - 2 * margin)
    let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185, yRadius: 185)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.23, alpha: 1),
        NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.09, alpha: 1),
    ])!.draw(in: bg, angle: -90)

    bg.addClip()

    // Back window — the buried source window
    let back = NSBezierPath(roundedRect: NSRect(x: 205, y: 260, width: 470, height: 350), xRadius: 40, yRadius: 40)
    NSColor(calibratedWhite: 1, alpha: 0.07).setFill()
    back.fill()
    NSColor(calibratedWhite: 1, alpha: 0.28).setStroke()
    back.lineWidth = 12
    back.stroke()

    // Floating mirror — bright, overlapping top-right
    let mirrorRect = NSRect(x: 430, y: 430, width: 380, height: 280)
    let mirror = NSBezierPath(roundedRect: mirrorRect, xRadius: 34, yRadius: 34)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.shadowBlurRadius = 40
    NSGraphicsContext.current?.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    mirror.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.31, green: 0.82, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.18, green: 0.48, blue: 1.0, alpha: 1),
    ])!.draw(in: mirror, angle: -75)
    NSColor(calibratedWhite: 1, alpha: 0.65).setStroke()
    mirror.lineWidth = 8
    mirror.stroke()

    // Titlebar hint on the mirror
    NSColor(calibratedWhite: 1, alpha: 0.35).setFill()
    NSBezierPath(roundedRect: NSRect(x: mirrorRect.minX + 34, y: mirrorRect.maxY - 62, width: 120, height: 22),
                 xRadius: 11, yRadius: 11).fill()

    // Pin, angled, at the mirror's top-right corner
    let config = NSImage.SymbolConfiguration(pointSize: 210, weight: .semibold)
    if let pin = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let white = tinted(pin, .white)
        let context = NSGraphicsContext.current!.cgContext
        context.saveGState()
        context.translateBy(x: mirrorRect.maxX - 30, y: mirrorRect.maxY - 20)
        context.rotate(by: -0.6)
        let size = white.size
        white.draw(in: NSRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height),
                   from: .zero, operation: .sourceOver, fraction: 1)
        context.restoreGState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Assets")
try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

let master = renderMaster()
let masterPNG = assets.appendingPathComponent("icon-1024.png")
try! master.representation(using: .png, properties: [:])!.write(to: masterPNG)
print("wrote \(masterPNG.path)")
