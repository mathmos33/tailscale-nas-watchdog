import Cocoa

let sizes: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

guard let baseImage = NSImage(systemSymbolName: "externaldrive.connected.to.line.below", accessibilityDescription: nil) else {
    fatalError("symbol not found")
}

let tint = NSColor(calibratedWhite: 1.0, alpha: 1.0)
let bgColor = NSColor(calibratedWhite: 0.42, alpha: 1.0)

for (name, pixels) in sizes {
    let canvas = NSImage(size: NSSize(width: pixels, height: pixels))
    canvas.lockFocus()

    let bgRect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: pixels * 0.22, yRadius: pixels * 0.22)
    bgColor.setFill()
    bgPath.fill()

    let config = NSImage.SymbolConfiguration(pointSize: pixels * 0.56, weight: .medium)
    let symbol = (baseImage.withSymbolConfiguration(config) ?? baseImage)

    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    let imgRect = NSRect(origin: .zero, size: symbol.size)
    symbol.draw(in: imgRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    tint.set()
    imgRect.fill(using: .sourceAtop)
    tinted.unlockFocus()

    let origin = NSPoint(x: (pixels - symbol.size.width) / 2, y: (pixels - symbol.size.height) / 2)
    tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)

    canvas.unlockFocus()

    guard let tiff = canvas.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        continue
    }
    let path = "\(outDir)/\(name).png"
    try? png.write(to: URL(fileURLWithPath: path))
}
print("Icon PNGs written to \(outDir)")
