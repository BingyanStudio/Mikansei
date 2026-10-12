import AppKit
import ImageIO
import UniformTypeIdentifiers

let path = CommandLine.arguments[1]
let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.13, green: 0.36, blue: 0.29, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setFillColor(CGColor(red: 0.98, green: 0.97, blue: 0.92, alpha: 1))
context.addPath(CGPath(roundedRect: CGRect(x: 210, y: 160, width: 604, height: 704), cornerWidth: 70, cornerHeight: 70, transform: nil))
context.fillPath()
for (index, y) in [650.0, 490.0, 330.0].enumerated() {
    context.setStrokeColor(CGColor(red: 0.16, green: 0.43, blue: 0.35, alpha: 1))
    context.setLineWidth(18)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    if index < 2 {
        context.move(to: CGPoint(x: 300, y: y))
        context.addLine(to: CGPoint(x: 330, y: y - 30))
        context.addLine(to: CGPoint(x: 385, y: y + 35))
        context.strokePath()
    } else {
        context.addPath(CGPath(roundedRect: CGRect(x: 302, y: y - 28, width: 60, height: 60), cornerWidth: 13, cornerHeight: 13, transform: nil))
        context.strokePath()
    }
    context.setStrokeColor(CGColor(red: 0.16, green: 0.43, blue: 0.35, alpha: index == 2 ? 0.28 : 0.75))
    context.move(to: CGPoint(x: 447, y: y + 1))
    context.addLine(to: CGPoint(x: 704, y: y + 1))
    context.strokePath()
}
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))

if CommandLine.arguments.count > 2 {
    let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source = context.makeImage()!
    let icons: [(String, Int)] = [
        ("AppIcon20x20@2x", 40), ("AppIcon20x20@3x", 60),
        ("AppIcon29x29@2x", 58), ("AppIcon29x29@3x", 87),
        ("AppIcon40x40@2x", 80), ("AppIcon40x40@3x", 120),
        ("AppIcon60x60@2x", 120), ("AppIcon60x60@3x", 180),
        ("AppIcon20x20", 20), ("AppIcon29x29", 29), ("AppIcon40x40", 40),
        ("AppIcon76x76", 76), ("AppIcon76x76@2x", 152), ("AppIcon83.5x83.5@2x", 167)
    ]
    for (name, pixels) in icons {
        let scaled = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        scaled.interpolationQuality = .high
        scaled.draw(source, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let url = directory.appendingPathComponent(name + ".png")
        let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(output, scaled.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(output))
    }
}
