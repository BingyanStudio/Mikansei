import AppKit
import CoreGraphics

// Opaque, code-native flat checklist icon for the kraft-paper beta.
let output = CommandLine.arguments[1]
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.89, green: 0.79, blue: 0.65, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.setFillColor(CGColor(red: 0.97, green: 0.91, blue: 0.82, alpha: 1))
context.addPath(CGPath(roundedRect: CGRect(x: 190, y: 146, width: 644, height: 732),
    cornerWidth: 64, cornerHeight: 64, transform: nil))
context.fillPath()
context.setStrokeColor(CGColor(red: 0.50, green: 0.34, blue: 0.20, alpha: 1))
context.setLineWidth(36); context.setLineCap(.round); context.setLineJoin(.round)
context.move(to: CGPoint(x: 278, y: 699)); context.addLine(to: CGPoint(x: 321, y: 650))
context.addLine(to: CGPoint(x: 406, y: 752)); context.strokePath()
context.setLineWidth(18)
for y in [518.0, 338.0] { context.strokeEllipse(in: CGRect(x: 283, y: y - 32, width: 66, height: 66)) }
context.setLineWidth(25)
for (y, width) in [(698.0, 276.0), (518.0, 252.0), (338.0, 186.0)] {
    context.move(to: CGPoint(x: 456, y: y)); context.addLine(to: CGPoint(x: 456 + width, y: y)); context.strokePath()
}
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
