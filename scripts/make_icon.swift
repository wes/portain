// Renders Portain's app icon to an .iconset and packs it into AppIcon.icns.
// Run: swift scripts/make_icon.swift
import AppKit

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // Rounded-rect macOS icon shape with a deep gradient.
    let corner = size * 0.2237
    let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    path.addClip()

    let colors = [
        NSColor(calibratedRed: 0.20, green: 0.55, blue: 1.00, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.36, green: 0.30, blue: 0.95, alpha: 1).cgColor
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: size),
                           end: CGPoint(x: size, y: 0),
                           options: [])

    // Soft top highlight.
    NSColor.white.withAlphaComponent(0.12).setFill()
    NSBezierPath(roundedRect: CGRect(x: 0, y: size * 0.55, width: size, height: size * 0.45),
                 xRadius: corner, yRadius: corner).fill()

    // Centered glyph: a network/port motif.
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted",
                            accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        NSColor.white.set()
        let r = CGRect(origin: .zero, size: symbol.size)
        symbol.draw(in: r)
        r.fill(using: .sourceAtop)
        tinted.unlockFocus()

        let gw = symbol.size.width
        let gh = symbol.size.height
        let origin = CGPoint(x: (size - gw) / 2, y: (size - gh) / 2)
        tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 0.95)
    }

    image.unlockFocus()
    return image
}

func png(_ image: NSImage, _ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let here = URL(fileURLWithPath: CommandLine.arguments.first ?? ".").deletingLastPathComponent()
let iconset = here.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let master = renderIcon(size: 1024)
let specs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, px) in specs {
    let data = png(master, px)
    try! data.write(to: iconset.appendingPathComponent("\(name).png"))
}
print("Wrote \(iconset.path)")
