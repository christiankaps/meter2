import AppKit
import CoreGraphics
import Foundation

struct IconVariant {
    let name: String
    let sourceFilename: String
}

let outputRoot = URL(fileURLWithPath: "Resources/AppIcon", isDirectory: true)
let assetCatalogRoot = URL(fileURLWithPath: "Resources/Assets.xcassets", isDirectory: true)

let variants = [
    IconVariant(name: "Light", sourceFilename: "app-icon-light-1024.png"),
    IconVariant(name: "Dark", sourceFilename: "app-icon-dark-1024.png"),
    IconVariant(name: "Tinted", sourceFilename: "app-icon-tinted-1024.png")
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

let sourceImages = try Dictionary(uniqueKeysWithValues: variants.map { variant in
    (variant.name, try loadSourceImage(named: variant.sourceFilename))
})

try removeGeneratedOutputs()
try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: assetCatalogRoot, withIntermediateDirectories: true)
try writeAssetCatalogContents(to: assetCatalogRoot)

let variantAppIconDirectory = assetCatalogRoot.appendingPathComponent("AppIconVariants.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: variantAppIconDirectory, withIntermediateDirectories: true)

for variant in variants {
    let sourceImage = sourceImages[variant.name]!
    let variantDirectory = outputRoot.appendingPathComponent("AppIcon\(variant.name).iconset", isDirectory: true)
    let appIconName = variant.name == "Light" ? "AppIcon" : "AppIcon\(variant.name)"
    let appIconDirectory = assetCatalogRoot.appendingPathComponent("\(appIconName).appiconset", isDirectory: true)
    try FileManager.default.createDirectory(at: variantDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: appIconDirectory, withIntermediateDirectories: true)

    for size in iconSizes {
        let image = try sourceImage.resized(to: size.pixels)
        try image.writePNG(to: variantDirectory.appendingPathComponent(size.name))
        try image.writePNG(to: appIconDirectory.appendingPathComponent(size.name))
        if variant.name == "Light" {
            try image.writePNG(to: variantAppIconDirectory.appendingPathComponent(size.name))
        }
    }

    try sourceImage.resized(to: 1024).writePNG(to: outputRoot.appendingPathComponent(variant.sourceFilename))
    try writeAppIconContents(to: appIconDirectory)
}

try writeVariantAppIconContents(to: variantAppIconDirectory)
try writeCompanionAppIcon(from: sourceImages["Light"]!)

print("Generated app icon PNGs in \(outputRoot.path)")
print("Generated Xcode asset catalog app icons in \(assetCatalogRoot.path)")

func loadSourceImage(named filename: String) throws -> NSImage {
    let url = outputRoot.appendingPathComponent(filename)
    guard let image = NSImage(contentsOf: url) else {
        throw IconGenerationError.sourceImageMissing(url.path)
    }
    return image
}

extension NSImage {
    func resized(to pixels: Int) throws -> NSImage {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw IconGenerationError.imageDecodingFailed
        }

        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        bitmap.size = NSSize(width: pixels, height: pixels)

        let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        defer { NSGraphicsContext.restoreGraphicsState() }

        let context = graphicsContext.cgContext
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))

        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.addRepresentation(bitmap)
        return image
    }

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

enum IconGenerationError: Error {
    case imageDecodingFailed
    case pngEncodingFailed(String)
    case sourceImageMissing(String)
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
        assetCatalogRoot.appendingPathComponent("AppIconVariants.appiconset", isDirectory: true),
        assetCatalogRoot.appendingPathComponent("CompanionAppIcon.appiconset", isDirectory: true)
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
    try (contents + "\n").write(to: directory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

func writeVariantAppIconContents(to directory: URL) throws {
    var entries: [String] = []

    for size in iconSizes {
        let sizeName = assetSlotSize(for: size.name)
        let scaleName = size.name.contains("@2x") ? "2x" : "1x"
        let entry = """
            {
              "filename" : "\(size.name)",
              "idiom" : "mac",
              "scale" : "\(scaleName)",
              "size" : "\(sizeName)"
            }
        """
        entries.append(entry)
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
    try (contents + "\n").write(to: directory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
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
    try (contents + "\n").write(to: directory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

func writeCompanionAppIcon(from sourceImage: NSImage) throws {
    let directory = assetCatalogRoot.appendingPathComponent("CompanionAppIcon.appiconset", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try sourceImage.resized(to: 1024).writePNG(to: directory.appendingPathComponent("companion_icon_1024.png"))

    let contents = """
    {
      "images" : [
        {
          "filename" : "companion_icon_1024.png",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
    try (contents + "\n").write(to: directory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}
