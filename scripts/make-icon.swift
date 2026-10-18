// Draws the Halfpast icon (1024 px PNG): a navy tile, a clock at half past, a small notch at
// the top edge where the app lives, and the Trilegal ribbon along the bottom.
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let cg = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// The tile, with macOS's margin around it.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
cg.saveGState()
cg.addPath(tilePath)
cg.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0x0B2238), color(0x004165)] as CFArray, locations: [0, 1])!
cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])

// The ribbon: five bands along the bottom edge.
let ribbon: [UInt32] = [0x004165, 0x0094B3, 0xAA272F, 0xFF6D22, 0x636467]
for (i, c) in ribbon.enumerated() {
    cg.setFillColor(color(c))
    cg.fill(CGRect(x: tile.minX + CGFloat(i) * tile.width / 5, y: tile.minY, width: tile.width / 5 + 1, height: 46))
}

// The notch: a black tab hanging from the top edge.
let notch = CGRect(x: 512 - 130, y: tile.maxY - 64, width: 260, height: 90)
cg.setFillColor(color(0x000000))
cg.addPath(CGPath(roundedRect: notch, cornerWidth: 30, cornerHeight: 30, transform: nil))
cg.fillPath()
cg.restoreGState()

// The clock: a pale face reading half past ten.
let c = CGPoint(x: 512, y: 488), r: CGFloat = 268
cg.setFillColor(color(0xF2F6F9))
cg.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
for h in 0..<12 {
    let a = CGFloat(h) / 12 * 2 * .pi
    let long = h % 3 == 0
    let r0 = r - (long ? 58 : 40), r1 = r - 22
    cg.setStrokeColor(long ? color(0x0094B3) : color(0x0B2238, 0.35))
    cg.setLineWidth(long ? 18 : 10)
    cg.setLineCap(.round)
    cg.move(to: CGPoint(x: c.x + r0 * sin(a), y: c.y + r0 * cos(a)))
    cg.addLine(to: CGPoint(x: c.x + r1 * sin(a), y: c.y + r1 * cos(a)))
    cg.strokePath()
}
func hand(_ turns: CGFloat, _ length: CGFloat, _ width: CGFloat, _ col: CGColor) {
    let a = turns * 2 * .pi
    cg.setStrokeColor(col)
    cg.setLineWidth(width)
    cg.setLineCap(.round)
    cg.move(to: c)
    cg.addLine(to: CGPoint(x: c.x + length * sin(a), y: c.y + length * cos(a)))
    cg.strokePath()
}
hand(10.5 / 12, 150, 34, color(0x0B2238))   // hour hand, halfway between 10 and 11
hand(0.5, 214, 24, color(0x0B2238))         // minute hand on the half hour
cg.setFillColor(color(0xFF6D22))
cg.fillEllipse(in: CGRect(x: c.x - 26, y: c.y - 26, width: 52, height: 52))

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
