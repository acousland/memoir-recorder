import AppKit

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let bundleURL = rootURL.appendingPathComponent("Bundle", isDirectory: true)
let iconsetURL = bundleURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icnsURL = bundleURL.appendingPathComponent("AppIcon.icns")

try? fileManager.removeItem(at: iconsetURL)
try? fileManager.removeItem(at: icnsURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let shadow = NSShadow()
    shadow.shadowColor = color(20, 40, 52, 0.28)
    shadow.shadowBlurRadius = size * 0.06
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.02)
    shadow.set()

    let base = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.05, dy: size * 0.05), xRadius: size * 0.24, yRadius: size * 0.24)
    let gradient = NSGradient(colors: [
        color(246, 196, 79),
        color(234, 142, 61),
        color(202, 79, 55)
    ])!
    gradient.draw(in: base, angle: 300)

    NSGraphicsContext.current?.saveGraphicsState()
    base.addClip()

    let topGlow = NSBezierPath(ovalIn: NSRect(x: size * 0.05, y: size * 0.48, width: size * 0.90, height: size * 0.48))
    color(255, 255, 255, 0.22).setFill()
    topGlow.fill()

    let notebookRect = NSRect(x: size * 0.22, y: size * 0.20, width: size * 0.56, height: size * 0.62)
    let notebook = NSBezierPath(roundedRect: notebookRect, xRadius: size * 0.09, yRadius: size * 0.09)
    color(255, 248, 238).setFill()
    notebook.fill()

    let notebookShadow = NSBezierPath(roundedRect: notebookRect.insetBy(dx: size * 0.012, dy: size * 0.012), xRadius: size * 0.08, yRadius: size * 0.08)
    color(225, 180, 123, 0.25).setStroke()
    notebookShadow.lineWidth = size * 0.018
    notebookShadow.stroke()

    let bindingX = notebookRect.minX + size * 0.07
    for index in 0..<3 {
        let y = notebookRect.maxY - size * (0.13 + CGFloat(index) * 0.16)
        let ring = NSBezierPath(ovalIn: NSRect(x: bindingX, y: y, width: size * 0.08, height: size * 0.08))
        color(214, 110, 58).setFill()
        ring.fill()
    }

    let waveform = NSBezierPath()
    waveform.lineCapStyle = .round
    waveform.lineJoinStyle = .round
    waveform.lineWidth = size * 0.048
    let startX = notebookRect.minX + size * 0.14
    let endX = notebookRect.maxX - size * 0.10
    let midY = notebookRect.midY - size * 0.02
    waveform.move(to: NSPoint(x: startX, y: midY))
    waveform.curve(to: NSPoint(x: startX + size * 0.12, y: midY + size * 0.07), controlPoint1: NSPoint(x: startX + size * 0.03, y: midY), controlPoint2: NSPoint(x: startX + size * 0.07, y: midY + size * 0.08))
    waveform.curve(to: NSPoint(x: startX + size * 0.22, y: midY - size * 0.08), controlPoint1: NSPoint(x: startX + size * 0.15, y: midY + size * 0.06), controlPoint2: NSPoint(x: startX + size * 0.18, y: midY - size * 0.08))
    waveform.curve(to: NSPoint(x: startX + size * 0.33, y: midY + size * 0.11), controlPoint1: NSPoint(x: startX + size * 0.26, y: midY - size * 0.08), controlPoint2: NSPoint(x: startX + size * 0.29, y: midY + size * 0.11))
    waveform.curve(to: NSPoint(x: endX, y: midY - size * 0.02), controlPoint1: NSPoint(x: startX + size * 0.38, y: midY + size * 0.11), controlPoint2: NSPoint(x: endX - size * 0.08, y: midY - size * 0.02))
    color(54, 79, 94).setStroke()
    waveform.stroke()

    let pulse = NSBezierPath(ovalIn: NSRect(x: notebookRect.maxX - size * 0.14, y: notebookRect.minY + size * 0.12, width: size * 0.10, height: size * 0.10))
    color(231, 103, 64).setFill()
    pulse.fill()

    NSGraphicsContext.current?.restoreGraphicsState()
    image.unlockFocus()
    return image
}

for (size, filename) in sizes {
    let image = drawIcon(size: CGFloat(size))
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGeneration", code: 1)
    }
    try png.write(to: iconsetURL.appendingPathComponent(filename))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "IconGeneration", code: Int(process.terminationStatus))
}

print("Created \(icnsURL.path)")
