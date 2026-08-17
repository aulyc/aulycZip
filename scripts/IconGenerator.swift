import AppKit
import CryptoKit
import Foundation

enum GeneratorError: Error, CustomStringConvertible {
    case invalidArguments
    case invalidSource
    case renderFailed(Int)
    case iconutilFailed(Int32)

    var description: String {
        switch self {
        case .invalidArguments: "usage: IconGenerator.swift <source-root> <output-root>"
        case .invalidSource: "iconMark.svg does not contain the expected canonical mark"
        case .renderFailed(let size): "failed to render icon at \(size)x\(size)"
        case .iconutilFailed(let status): "iconutil failed with status \(status)"
        }
    }
}

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func render(svg: Data, pixels: Int, to destination: URL) throws {
    guard let image = NSImage(data: svg),
          let representation = NSBitmapImageRep(
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
          ) else {
        throw GeneratorError.renderFailed(pixels)
    }

    representation.size = NSSize(width: pixels, height: pixels)
    guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
        throw GeneratorError.renderFailed(pixels)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = representation.representation(using: .png, properties: [:]) else {
        throw GeneratorError.renderFailed(pixels)
    }
    try png.write(to: destination, options: .atomic)
}

func generate(sourceRoot: URL, outputRoot: URL) throws {
    let fileManager = FileManager.default
    let sourceURL = sourceRoot.appendingPathComponent("design/iconMark.svg")
    let canonical = try String(contentsOf: sourceURL, encoding: .utf8)
    guard canonical.contains("id=\"aulyczip-icon-mark\""),
          canonical.contains("stroke=\"#000000\"") else {
        throw GeneratorError.invalidSource
    }

    let menuSVG = canonical.replacingOccurrences(
        of: "viewBox=\"0 0 1024 1024\"",
        with: "viewBox=\"204 212 640 640\""
    ).replacingOccurrences(
        of: "stroke-width=\"50\"",
        with: "stroke-width=\"40\""
    ).replacingOccurrences(
        of: "stroke-width=\"58\"",
        with: "stroke-width=\"46\""
    )
    let background = "  <rect x=\"38\" y=\"38\" width=\"948\" height=\"948\" rx=\"218\" fill=\"#303034\"/>\n"
    let appSVG = canonical
        .replacingOccurrences(of: "<g id=\"aulyczip-icon-mark\"", with: background + "  <g id=\"aulyczip-icon-mark\"")
        .replacingOccurrences(of: "stroke=\"#000000\"", with: "stroke=\"#DADADF\"")

    let designDirectory = outputRoot.appendingPathComponent("design", isDirectory: true)
    let sourceResourceDirectory = outputRoot.appendingPathComponent("Sources/aulycZip/Resources", isDirectory: true)
    let resourcesDirectory = outputRoot.appendingPathComponent("Resources", isDirectory: true)
    try fileManager.createDirectory(at: designDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: sourceResourceDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)

    let menuData = Data(menuSVG.utf8)
    let appData = Data(appSVG.utf8)
    try menuData.write(to: designDirectory.appendingPathComponent("menuBarIcon.svg"), options: .atomic)
    try menuData.write(to: sourceResourceDirectory.appendingPathComponent("MenuBarIcon.svg"), options: .atomic)
    try appData.write(to: designDirectory.appendingPathComponent("appIcon.svg"), options: .atomic)
    try render(svg: appData, pixels: 512, to: designDirectory.appendingPathComponent("appIcon-preview.png"))

    let iconset = outputRoot.appendingPathComponent(".icon-generation/AppIcon.iconset", isDirectory: true)
    try? fileManager.removeItem(at: iconset.deletingLastPathComponent())
    try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
    let variants: [(String, Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    for (name, pixels) in variants {
        try render(svg: appData, pixels: pixels, to: iconset.appendingPathComponent(name))
    }

    let icnsURL = resourcesDirectory.appendingPathComponent("AppIcon.icns")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw GeneratorError.iconutilFailed(process.terminationStatus)
    }
    try? fileManager.removeItem(at: iconset.deletingLastPathComponent())

    let manifest: [String: String] = [
        "canonical": sha256(Data(canonical.utf8)),
        "menuBar": sha256(menuData),
        "appSVG": sha256(appData),
        "appICNS": sha256(try Data(contentsOf: icnsURL)),
    ]
    let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    try manifestData.write(to: designDirectory.appendingPathComponent("icon-manifest.json"), options: .atomic)
}

do {
    guard CommandLine.arguments.count == 3 else { throw GeneratorError.invalidArguments }
    try generate(
        sourceRoot: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true),
        outputRoot: URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    )
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
