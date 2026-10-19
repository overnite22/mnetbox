import AppKit
import CoreGraphics

// Original vector rack illustration. RGB without alpha, including every background pixel.
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                              bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
      let gradient = CGGradient(colorsSpace: colorSpace, colors: [
        CGColor(red: 0.04, green: 0.12, blue: 0.24, alpha: 1),
        CGColor(red: 0.08, green: 0.39, blue: 0.67, alpha: 1)
      ] as CFArray, locations: [0, 1]) else { fatalError("Unable to create icon context") }
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1024, y: 1024), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
let rack = CGPath(roundedRect: CGRect(x: 244, y: 170, width: 536, height: 684), cornerWidth: 52, cornerHeight: 52, transform: nil)
context.setStrokeColor(CGColor(gray: 1, alpha: 0.95)); context.setLineWidth(26)
context.addPath(rack); context.strokePath()
for y in [270, 442, 614] {
    let slot = CGPath(roundedRect: CGRect(x: 294, y: y, width: 436, height: 128), cornerWidth: 20, cornerHeight: 20, transform: nil)
    context.setFillColor(CGColor(gray: 1, alpha: 0.14)); context.addPath(slot); context.fillPath()
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.9)); context.setLineWidth(10); context.addPath(slot); context.strokePath()
    context.setFillColor(CGColor(red: 0.25, green: 0.96, blue: 0.76, alpha: 1))
    context.fillEllipse(in: CGRect(x: 632, y: y + 49, width: 30, height: 30))
    context.setFillColor(CGColor(gray: 1, alpha: 0.85))
    for x in [330, 356, 382, 408] {
        context.addPath(CGPath(roundedRect: CGRect(x: x, y: y + 42, width: 10, height: 44), cornerWidth: 5, cornerHeight: 5, transform: nil)); context.fillPath()
    }
}
guard let image = context.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { fatalError("Unable to encode icon") }
try png.write(to: URL(fileURLWithPath: "MNetBox/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
