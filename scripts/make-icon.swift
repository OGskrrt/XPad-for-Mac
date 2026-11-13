// Draws the XPad app icon (1024×1024 PNG). Usage: swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

// Background tile (macOS icon grid: 824pt tile, 100pt margin).
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
shadow.set()
rgb(0x15634A).setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: rgb(0x2FB37F), ending: rgb(0x0F523C))!.draw(in: tilePath, angle: -90)

// Controller silhouette.
let body = NSBezierPath()
body.append(NSBezierPath(roundedRect: NSRect(x: 236, y: 400, width: 552, height: 250), xRadius: 125, yRadius: 125))
body.append(NSBezierPath(ovalIn: NSRect(x: 214, y: 300, width: 250, height: 270)))
body.append(NSBezierPath(ovalIn: NSRect(x: 560, y: 300, width: 250, height: 270)))
body.windingRule = .nonZero
NSGraphicsContext.saveGraphicsState()
let s2 = NSShadow()
s2.shadowColor = NSColor.black.withAlphaComponent(0.22)
s2.shadowOffset = NSSize(width: 0, height: -10)
s2.shadowBlurRadius = 20
s2.set()
NSColor.white.setFill()
body.fill()
NSGraphicsContext.restoreGraphicsState()

// D-pad and face buttons cut in the tile colour.
let ink = rgb(0x17694F)
ink.setFill()
NSBezierPath(roundedRect: NSRect(x: 300, y: 501, width: 128, height: 42), xRadius: 10, yRadius: 10).fill()
NSBezierPath(roundedRect: NSRect(x: 343, y: 458, width: 42, height: 128), xRadius: 10, yRadius: 10).fill()
let c = NSPoint(x: 662, y: 522)
for (dx, dy) in [(0.0, 50.0), (0.0, -50.0), (-50.0, 0.0), (50.0, 0.0)] {
    NSBezierPath(ovalIn: NSRect(x: c.x + dx - 24, y: c.y + dy - 24, width: 48, height: 48)).fill()
}
// Little "plug" prongs on top: the app's idea, plug it in and it works.
rgb(0xFFFFFF).withAlphaComponent(0.92).setFill()
NSBezierPath(roundedRect: NSRect(x: 468, y: 650, width: 30, height: 96), xRadius: 12, yRadius: 12).fill()
NSBezierPath(roundedRect: NSRect(x: 526, y: 650, width: 30, height: 96), xRadius: 12, yRadius: 12).fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote", out)
