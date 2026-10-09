import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16,32,64,128,256,512,1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size) / 1024
    let transform = AffineTransform(scale: scale)
    (transform as NSAffineTransform).concat()
    let outer = NSBezierPath(roundedRect: NSRect(x: 52,y: 52,width: 920,height: 920), xRadius: 206,yRadius: 206)
    NSGradient(starting: NSColor(red: 0.12,green: 0.20,blue: 0.23,alpha: 1), ending: NSColor(red: 0.035,green: 0.09,blue: 0.12,alpha: 1))!.draw(in: outer, angle: -60)
    NSColor(red: 0.43,green: 0.88,blue: 0.75,alpha: 1).setStroke()
    let screen = NSBezierPath(roundedRect: NSRect(x: 226,y: 364,width: 572,height: 368),xRadius: 40,yRadius: 40); screen.lineWidth = 40; screen.stroke()
    let stem = NSBezierPath(); stem.lineWidth = 38; stem.lineCapStyle = .round; stem.move(to: NSPoint(x:512,y:354)); stem.line(to:NSPoint(x:512,y:262)); stem.move(to:NSPoint(x:388,y:260)); stem.line(to:NSPoint(x:636,y:260)); stem.stroke()
    let slash = NSBezierPath(); slash.lineWidth = 35; slash.lineCapStyle = .round; slash.lineJoinStyle = .round; slash.move(to:NSPoint(x:390,y:462)); slash.line(to:NSPoint(x:619,y:627)); slash.move(to:NSPoint(x:510,y:627)); slash.line(to:NSPoint(x:619,y:627)); slash.line(to:NSPoint(x:619,y:518)); slash.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    if size <= 512 { try png.write(to: directory.appendingPathComponent("icon_\(size)x\(size).png")) }
    if size >= 32 { try png.write(to: directory.appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png")) }
}
