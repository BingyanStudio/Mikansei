import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Export the approved artwork without redrawing it. iOS supplies the corner mask.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let arguments = CommandLine.arguments
let sourceURL = root.appendingPathComponent("App/Artwork/AppIconSource.png")
guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let source = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
      source.width == source.height else {
    fputs("无法读取正方形图标原稿：\(sourceURL.path)\n", stderr)
    exit(1)
}
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func export(pixels: Int, to url: URL) throws {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                            bytesPerRow: pixels * 4, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // App icons are opaque, including any transparent pixels in a future source.
    context.setFillColor(CGColor(red: 41.0 / 255, green: 107.0 / 255, blue: 92.0 / 255, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    context.interpolationQuality = .high
    context.draw(source, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let mainURL = arguments.count > 1 ? URL(fileURLWithPath: arguments[1]) :
    root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try export(pixels: 1024, to: mainURL)
let resources = arguments.count > 2 ? URL(fileURLWithPath: arguments[2], isDirectory: true) :
    arguments.count == 1 ? root.appendingPathComponent("App/Resources", isDirectory: true) : nil
if let resources {
    let icons: [(String, Int)] = [
        ("AppIcon20x20@2x", 40), ("AppIcon20x20@3x", 60),
        ("AppIcon29x29@2x", 58), ("AppIcon29x29@3x", 87),
        ("AppIcon40x40@2x", 80), ("AppIcon40x40@3x", 120),
        ("AppIcon60x60@2x", 120), ("AppIcon60x60@3x", 180),
        ("AppIcon20x20", 20), ("AppIcon29x29", 29), ("AppIcon40x40", 40),
        ("AppIcon76x76", 76), ("AppIcon76x76@2x", 152), ("AppIcon83.5x83.5@2x", 167)
    ]
    for (name, pixels) in icons {
        try export(pixels: pixels, to: resources.appendingPathComponent(name + ".png"))
    }
}
print("已导出选定角色图标：\(mainURL.path)")
