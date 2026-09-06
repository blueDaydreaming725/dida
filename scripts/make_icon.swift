// 生成 Dida 应用图标（HY 渐变字标，macOS squircle 规范）
// 用法: swift scripts/make_icon.swift <iconset目录>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"

func makeRep(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    return rep
}

func brandGradient() -> NSGradient {
    NSGradient(colors: [
        NSColor(srgbRed: 0.23, green: 0.51, blue: 0.96, alpha: 1),
        NSColor(srgbRed: 0.66, green: 0.33, blue: 0.96, alpha: 1),
        NSColor(srgbRed: 0.93, green: 0.28, blue: 0.60, alpha: 1),
    ])!
}

// 渲染 1024 母版：深底 squircle + HY 渐变字
func drawMaster() -> NSBitmapImageRep {
    let px = 1024
    let rep = makeRep(px)
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("no ctx") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let s = CGFloat(px)

    // macOS 图标画布：824/1024 居中，圆角 185/1024
    let inset = s * (1024 - 824) / 2 / 1024
    let box = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let squircle = NSBezierPath(roundedRect: box, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)

    NSGradient(colors: [
        NSColor(srgbRed: 0.047, green: 0.055, blue: 0.133, alpha: 1),
        NSColor(srgbRed: 0.082, green: 0.063, blue: 0.204, alpha: 1),
    ])!.draw(in: squircle, angle: -70)
    NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke()
    squircle.lineWidth = s * 2 / 1024
    squircle.stroke()

    // HY 字母：独立透明层绘制 → sourceAtop 只染字母
    let text = "HY"
    var fontSize = s * 360 / 1024
    var attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    ]
    var ts = (text as NSString).size(withAttributes: attrs)
    fontSize *= (box.width * 0.62) / ts.width
    attrs[.font] = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    attrs[.kern] = NSNumber(value: -Double(fontSize) * 0.03)
    ts = (text as NSString).size(withAttributes: attrs)

    let letterRep = makeRep(px)
    let letterCtx = NSGraphicsContext(bitmapImageRep: letterRep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = letterCtx
    let origin = NSPoint(x: (s - ts.width) / 2, y: (s - ts.height) / 2 - s * 0.012)
    (text as NSString).draw(at: origin, withAttributes: attrs)
    NSGraphicsContext.current?.compositingOperation = .sourceAtop
    brandGradient().draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: -60)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.current = ctx
    let letters = NSImage(cgImage: letterRep.cgImage!, size: NSSize(width: s, height: s))
    letters.draw(in: NSRect(x: 0, y: 0, width: s, height: s))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let master = drawMaster()
let masterImage = NSImage(cgImage: master.cgImage!, size: NSSize(width: 1024, height: 1024))

let fileManager = FileManager.default
try? fileManager.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let spec: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, px) in spec {
    let rep = makeRep(px)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    NSGraphicsContext.current?.imageInterpolation = .high
    masterImage.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: outDir + "/" + name))
}
print("iconset written to \(outDir)")
