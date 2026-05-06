import AppKit
import CoreGraphics
import Foundation

struct IconPalette {
    let name: String
    let backgroundTop: NSColor
    let backgroundBottom: NSColor
    let backgroundAccent: NSColor
    let primary: NSColor
    let secondary: NSColor
    let tertiary: NSColor
    let foreground: NSColor
    let grid: NSColor
    let shadow: NSColor
}

let outputRoot = URL(fileURLWithPath: "Resources/AppIcon", isDirectory: true)
let assetCatalogRoot = URL(fileURLWithPath: "Resources/Assets.xcassets", isDirectory: true)

let palettes = [
    IconPalette(
        name: "Light",
        backgroundTop: NSColor(hex: 0xF8FBFF),
        backgroundBottom: NSColor(hex: 0xDDEBFF),
        backgroundAccent: NSColor(hex: 0xBFE8EF),
        primary: NSColor(hex: 0x2867F0),
        secondary: NSColor(hex: 0x00A8B5),
        tertiary: NSColor(hex: 0x8BCF3F),
        foreground: NSColor(hex: 0x132033),
        grid: NSColor(hex: 0x5C78A8, alpha: 0.16),
        shadow: NSColor(hex: 0x385580, alpha: 0.26)
    ),
    IconPalette(
        name: "Dark",
        backgroundTop: NSColor(hex: 0x121E33),
        backgroundBottom: NSColor(hex: 0x06101E),
        backgroundAccent: NSColor(hex: 0x173E53),
        primary: NSColor(hex: 0x83A8FF),
        secondary: NSColor(hex: 0x58E8EA),
        tertiary: NSColor(hex: 0xB2F36D),
        foreground: NSColor(hex: 0xF5FAFF),
        grid: NSColor(hex: 0xC7D7FF, alpha: 0.14),
        shadow: NSColor(hex: 0x000000, alpha: 0.42)
    ),
    IconPalette(
        name: "Tinted",
        backgroundTop: NSColor(hex: 0xF4F4F4),
        backgroundBottom: NSColor(hex: 0xB9B9B9),
        backgroundAccent: NSColor(hex: 0xD7D7D7),
        primary: NSColor(hex: 0x1C1C1C),
        secondary: NSColor(hex: 0x5A5A5A),
        tertiary: NSColor(hex: 0x8A8A8A),
        foreground: NSColor(hex: 0x111111),
        grid: NSColor(hex: 0x000000, alpha: 0.12),
        shadow: NSColor(hex: 0x000000, alpha: 0.20)
    )
]

let iconSizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

try removeGeneratedOutputs()
try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: assetCatalogRoot, withIntermediateDirectories: true)
try writeAssetCatalogContents(to: assetCatalogRoot)

let variantAppIconDirectory = assetCatalogRoot.appendingPathComponent("AppIconVariants.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: variantAppIconDirectory, withIntermediateDirectories: true)

for palette in palettes {
    let variantDirectory = outputRoot.appendingPathComponent("AppIcon\(palette.name).iconset", isDirectory: true)
    let appIconName = palette.name == "Light" ? "AppIcon" : "AppIcon\(palette.name)"
    let appIconDirectory = assetCatalogRoot.appendingPathComponent("\(appIconName).appiconset", isDirectory: true)
    try FileManager.default.createDirectory(at: variantDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: appIconDirectory, withIntermediateDirectories: true)

    for size in iconSizes {
        let image = renderIcon(size: size.pixels, palette: palette)
        try image.writePNG(to: variantDirectory.appendingPathComponent(size.name))
        try image.writePNG(to: appIconDirectory.appendingPathComponent(size.name))
        try image.writePNG(to: variantAppIconDirectory.appendingPathComponent("\(palette.name.lowercased())_\(size.name)"))
    }

    let preview = renderIcon(size: 1024, palette: palette)
    try preview.writePNG(to: outputRoot.appendingPathComponent("app-icon-\(palette.name.lowercased())-1024.png"))
    try writeAppIconContents(to: appIconDirectory)
}

try writeVariantAppIconContents(to: variantAppIconDirectory)

print("Generated app icon PNGs in \(outputRoot.path)")
print("Generated Xcode asset catalog app icons in \(assetCatalogRoot.path)")

func renderIcon(size: Int, palette: IconPalette) -> NSImage {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bitmap.size = NSSize(width: size, height: size)

    let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    defer { NSGraphicsContext.restoreGraphicsState() }

    let canvas = CGSize(width: size, height: size)
    let context = graphicsContext.cgContext

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let scale = CGFloat(size) / 1024.0
    let rect = CGRect(origin: .zero, size: canvas)
    let iconRect = rect.insetBy(dx: 42 * scale, dy: 42 * scale)
    let radius = 216 * scale
    let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)

    drawSoftShadow(context: context, path: iconPath, color: palette.shadow, scale: scale)

    context.saveGState()
    iconPath.addClip()

    NSGradient(starting: palette.backgroundTop, ending: palette.backgroundBottom)?
        .draw(in: iconRect, angle: 122)

    drawBackgroundGlow(in: iconRect, palette: palette, scale: scale)
    drawGrid(in: iconRect, color: palette.grid, scale: scale)
    drawReadingMark(in: iconRect, palette: palette, scale: scale)

    context.restoreGState()

    drawInnerHighlight(in: iconRect, scale: scale)

    let image = NSImage(size: canvas)
    image.addRepresentation(bitmap)
    return image
}

func drawSoftShadow(context: CGContext, path: NSBezierPath, color: NSColor, scale: CGFloat) {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18 * scale), blur: 42 * scale, color: color.cgColor)
    NSColor.black.withAlphaComponent(0.08).setFill()
    path.fill()
    context.restoreGState()
}

func drawBackgroundGlow(in rect: CGRect, palette: IconPalette, scale: CGFloat) {
    let glowRect = CGRect(
        x: rect.minX + 522 * scale,
        y: rect.minY + 504 * scale,
        width: 416 * scale,
        height: 392 * scale
    )
    let glowPath = NSBezierPath(ovalIn: glowRect)
    NSGradient(
        colors: [
            palette.backgroundAccent.withAlphaComponent(0.78),
            palette.backgroundAccent.withAlphaComponent(0.10),
            palette.backgroundAccent.withAlphaComponent(0.0)
        ]
    )?.draw(in: glowPath, relativeCenterPosition: NSPoint(x: -0.18, y: 0.22))
}

func drawGrid(in rect: CGRect, color: NSColor, scale: CGFloat) {
    color.setStroke()

    for index in 0..<7 {
        let path = NSBezierPath()
        path.lineWidth = max(1, 2.2 * scale)
        let x = rect.minX + CGFloat(154 + index * 112) * scale
        path.move(to: CGPoint(x: x, y: rect.minY + 138 * scale))
        path.line(to: CGPoint(x: x + 128 * scale, y: rect.maxY - 126 * scale))
        path.stroke()
    }

    for index in 0..<5 {
        let path = NSBezierPath()
        path.lineWidth = max(1, 1.8 * scale)
        let y = rect.minY + CGFloat(198 + index * 122) * scale
        path.move(to: CGPoint(x: rect.minX + 112 * scale, y: y))
        path.line(to: CGPoint(x: rect.maxX - 112 * scale, y: y + 44 * scale))
        path.stroke()
    }
}

func drawReadingMark(in rect: CGRect, palette: IconPalette, scale: CGFloat) {
    let panelRect = CGRect(
        x: rect.minX + 178 * scale,
        y: rect.minY + 206 * scale,
        width: 668 * scale,
        height: 574 * scale
    )
    let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: 92 * scale, yRadius: 92 * scale)
    palette.foreground.withAlphaComponent(0.055).setFill()
    panelPath.fill()

    let baseline = NSBezierPath()
    baseline.lineWidth = max(2, 16 * scale)
    baseline.lineCapStyle = .round
    palette.foreground.withAlphaComponent(0.22).setStroke()
    baseline.move(to: CGPoint(x: rect.minX + 244 * scale, y: rect.minY + 292 * scale))
    baseline.line(to: CGPoint(x: rect.minX + 780 * scale, y: rect.minY + 292 * scale))
    baseline.stroke()

    let bars: [(x: CGFloat, height: CGFloat, color: NSColor)] = [
        (306, 236, palette.secondary),
        (428, 356, palette.primary),
        (550, 284, palette.tertiary)
    ]

    for bar in bars {
        let barRect = CGRect(
            x: rect.minX + bar.x * scale,
            y: rect.minY + 292 * scale,
            width: 78 * scale,
            height: bar.height * scale
        )
        let path = NSBezierPath(roundedRect: barRect, xRadius: 39 * scale, yRadius: 39 * scale)
        NSGradient(
            starting: bar.color.withAlphaComponent(0.96),
            ending: bar.color.blended(withFraction: 0.34, of: palette.foreground) ?? bar.color
        )?.draw(in: path, angle: 90)

        palette.foreground.withAlphaComponent(0.12).setStroke()
        path.lineWidth = max(1, 3 * scale)
        path.stroke()

        let pointRect = CGRect(
            x: barRect.midX - 24 * scale,
            y: barRect.maxY + 24 * scale,
            width: 48 * scale,
            height: 48 * scale
        )
        bar.color.setFill()
        NSBezierPath(ovalIn: pointRect).fill()
    }

    drawForecastCurve(in: rect, palette: palette, scale: scale)
}

func drawForecastCurve(in rect: CGRect, palette: IconPalette, scale: CGFloat) {
    let solid = NSBezierPath()
    solid.lineWidth = max(3, 20 * scale)
    solid.lineCapStyle = .round
    solid.lineJoinStyle = .round
    palette.foreground.withAlphaComponent(0.82).setStroke()
    solid.move(to: CGPoint(x: rect.minX + 330 * scale, y: rect.minY + 542 * scale))
    solid.curve(
        to: CGPoint(x: rect.minX + 572 * scale, y: rect.minY + 646 * scale),
        controlPoint1: CGPoint(x: rect.minX + 410 * scale, y: rect.minY + 604 * scale),
        controlPoint2: CGPoint(x: rect.minX + 486 * scale, y: rect.minY + 612 * scale)
    )
    solid.stroke()

    let dashed = NSBezierPath()
    dashed.lineWidth = max(3, 20 * scale)
    dashed.lineCapStyle = .round
    dashed.lineJoinStyle = .round
    dashed.setLineDash([32 * scale, 28 * scale], count: 2, phase: 0)
    palette.primary.withAlphaComponent(0.92).setStroke()
    dashed.move(to: CGPoint(x: rect.minX + 572 * scale, y: rect.minY + 646 * scale))
    dashed.curve(
        to: CGPoint(x: rect.minX + 752 * scale, y: rect.minY + 704 * scale),
        controlPoint1: CGPoint(x: rect.minX + 636 * scale, y: rect.minY + 688 * scale),
        controlPoint2: CGPoint(x: rect.minX + 690 * scale, y: rect.minY + 704 * scale)
    )
    dashed.stroke()

    let endpoint = CGRect(
        x: rect.minX + 728 * scale,
        y: rect.minY + 680 * scale,
        width: 56 * scale,
        height: 56 * scale
    )
    palette.primary.setFill()
    NSBezierPath(ovalIn: endpoint).fill()

    palette.foreground.withAlphaComponent(0.75).setStroke()
    let endpointRing = NSBezierPath(ovalIn: endpoint.insetBy(dx: -8 * scale, dy: -8 * scale))
    endpointRing.lineWidth = max(1, 4 * scale)
    endpointRing.stroke()
}

func drawInnerHighlight(in rect: CGRect, scale: CGFloat) {
    let highlight = NSBezierPath(roundedRect: rect.insetBy(dx: 8 * scale, dy: 8 * scale), xRadius: 204 * scale, yRadius: 204 * scale)
    NSColor.white.withAlphaComponent(0.18).setStroke()
    highlight.lineWidth = max(1, 3 * scale)
    highlight.stroke()
}

extension NSImage {
    func writePNG(to url: URL) throws {
        guard
            let tiffData = tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw IconGenerationError.pngEncodingFailed(url.path)
        }

        try pngData.write(to: url)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let red = CGFloat((hex & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((hex & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(hex & 0x0000FF) / 255.0
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

enum IconGenerationError: Error {
    case pngEncodingFailed(String)
}

func removeGeneratedOutputs() throws {
    let generatedPaths = [
        outputRoot.appendingPathComponent("AppIconLight.iconset", isDirectory: true),
        outputRoot.appendingPathComponent("AppIconDark.iconset", isDirectory: true),
        outputRoot.appendingPathComponent("AppIconTinted.iconset", isDirectory: true),
        outputRoot.appendingPathComponent("app-icon-light-1024.png"),
        outputRoot.appendingPathComponent("app-icon-dark-1024.png"),
        outputRoot.appendingPathComponent("app-icon-tinted-1024.png"),
        assetCatalogRoot.appendingPathComponent("AppIcon.appiconset", isDirectory: true),
        assetCatalogRoot.appendingPathComponent("AppIconDark.appiconset", isDirectory: true),
        assetCatalogRoot.appendingPathComponent("AppIconTinted.appiconset", isDirectory: true),
        assetCatalogRoot.appendingPathComponent("AppIconVariants.appiconset", isDirectory: true)
    ]

    for path in generatedPaths where FileManager.default.fileExists(atPath: path.path) {
        try FileManager.default.removeItem(at: path)
    }
}

func writeAssetCatalogContents(to directory: URL) throws {
    let contents = """
    {
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
    try contents.write(to: directory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

func writeVariantAppIconContents(to directory: URL) throws {
    var entries: [String] = []

    for palette in palettes {
        for size in iconSizes {
            let sizeName = assetSlotSize(for: size.name)
            let scaleName = size.name.contains("@2x") ? "2x" : "1x"
            let appearance = appearanceBlock(for: palette.name)
            let entry = """
                {
            \(appearance)\
                  "filename" : "\(palette.name.lowercased())_\(size.name)",
                  "idiom" : "mac",
                  "scale" : "\(scaleName)",
                  "size" : "\(sizeName)"
                }
            """
            entries.append(entry)
        }
    }

    let contents = """
    {
      "images" : [
    \(entries.joined(separator: ",\n"))
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
    try contents.write(to: directory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

func appearanceBlock(for paletteName: String) -> String {
    switch paletteName {
    case "Dark":
        return """
                  "appearances" : [
                    {
                      "appearance" : "luminosity",
                      "value" : "dark"
                    }
                  ],

        """
    case "Tinted":
        return """
                  "appearances" : [
                    {
                      "appearance" : "luminosity",
                      "value" : "tinted"
                    }
                  ],

        """
    default:
        return ""
    }
}

func assetSlotSize(for filename: String) -> String {
    if filename.hasPrefix("icon_16x16") {
        return "16x16"
    }
    if filename.hasPrefix("icon_32x32") {
        return "32x32"
    }
    if filename.hasPrefix("icon_128x128") {
        return "128x128"
    }
    if filename.hasPrefix("icon_256x256") {
        return "256x256"
    }
    return "512x512"
}

func writeAppIconContents(to directory: URL) throws {
    let contents = """
    {
      "images" : [
        {
          "filename" : "icon_16x16.png",
          "idiom" : "mac",
          "scale" : "1x",
          "size" : "16x16"
        },
        {
          "filename" : "icon_16x16@2x.png",
          "idiom" : "mac",
          "scale" : "2x",
          "size" : "16x16"
        },
        {
          "filename" : "icon_32x32.png",
          "idiom" : "mac",
          "scale" : "1x",
          "size" : "32x32"
        },
        {
          "filename" : "icon_32x32@2x.png",
          "idiom" : "mac",
          "scale" : "2x",
          "size" : "32x32"
        },
        {
          "filename" : "icon_128x128.png",
          "idiom" : "mac",
          "scale" : "1x",
          "size" : "128x128"
        },
        {
          "filename" : "icon_128x128@2x.png",
          "idiom" : "mac",
          "scale" : "2x",
          "size" : "128x128"
        },
        {
          "filename" : "icon_256x256.png",
          "idiom" : "mac",
          "scale" : "1x",
          "size" : "256x256"
        },
        {
          "filename" : "icon_256x256@2x.png",
          "idiom" : "mac",
          "scale" : "2x",
          "size" : "256x256"
        },
        {
          "filename" : "icon_512x512.png",
          "idiom" : "mac",
          "scale" : "1x",
          "size" : "512x512"
        },
        {
          "filename" : "icon_512x512@2x.png",
          "idiom" : "mac",
          "scale" : "2x",
          "size" : "512x512"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
    try contents.write(to: directory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}
