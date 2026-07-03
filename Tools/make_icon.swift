// Génère l'icône de l'app par code (Core Graphics) : dégradé + barres de son avec un écho
// décalé (le motif « délai »). Produit Resources/AppIcon.iconset/*.png.
// Usage : swift Tools/make_icon.swift   (puis iconutil -c icns ... → AppIcon.icns)
import AppKit

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    let cg = gctx.cgContext

    let full = CGRect(x: 0, y: 0, width: size, height: size)
    // Marge transparente (les icônes macOS ne remplissent pas tout le carré).
    let margin = size * 0.08
    let bg = full.insetBy(dx: margin, dy: margin)
    let radius = bg.width * 0.2237   // coin « squircle » approché

    // Fond dégradé bleu → indigo.
    let bgPath = CGPath(roundedRect: bg, cornerWidth: radius, cornerHeight: radius, transform: nil)
    cg.saveGState()
    cg.addPath(bgPath); cg.clip()
    let colors = [NSColor(srgbRed: 0.33, green: 0.45, blue: 0.98, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.45, green: 0.24, blue: 0.86, alpha: 1).cgColor] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                          locations: [0, 1])!
    cg.drawLinearGradient(grad, start: CGPoint(x: bg.midX, y: bg.maxY),
                          end: CGPoint(x: bg.midX, y: bg.minY), options: [])
    cg.restoreGState()

    // Barres de son centrées + écho décalé (le « délai »).
    let heights: [CGFloat] = [0.40, 0.70, 1.0, 0.58, 0.32]
    let n = heights.count
    let area = bg.insetBy(dx: bg.width * 0.24, dy: bg.height * 0.28)
    let barW = area.width / (CGFloat(n) * 1.8)
    let step = (area.width - barW) / CGFloat(n - 1)

    func drawBars(dx: CGFloat, alpha: CGFloat) {
        cg.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
        for i in 0..<n {
            let h = area.height * heights[i]
            let x = area.minX + CGFloat(i) * step + dx
            let y = area.midY - h / 2
            let r = CGRect(x: x, y: y, width: barW, height: h)
            cg.addPath(CGPath(roundedRect: r, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
            cg.fillPath()
        }
    }
    let echo = bg.width * 0.055
    drawBars(dx: echo, alpha: 0.30)   // écho décalé, estompé
    drawBars(dx: 0, alpha: 1.0)        // barres principales

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("Resources/AppIcon.iconset")
try? fm.createDirectory(at: iconset, withIntermediateDirectories: true)

// (nom de fichier, pixels) pour un iconset macOS complet.
let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in variants {
    let rep = drawIcon(pixels: px)
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: iconset.appendingPathComponent("\(name).png"))
}
print("iconset généré : \(iconset.path)")
