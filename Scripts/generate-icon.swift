import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let titles = ["Pixel Mandala", "Mosaic Lotus", "Spectrum Weave", "Prism Bloom", "Pixel Orbit", "Radiant Star"]
let descriptions = ["Concentric diamonds around a single pixel", "Eight petals made from tiny color tiles", "Interlocking steps with a bright center", "A geometric flower of layered pixels", "Color rings with a selected center pixel", "A rangoli star on a crisp pixel grid"]
let palette: [UInt32] = [0xFF5C67, 0xEF813A, 0xF3BA43, 0x69B74B, 0x20AEAA, 0x318BDC, 0x7761DD, 0xCA57B5]

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func sector(_ x: CGFloat, _ y: CGFloat) -> Int {
    (Int((atan2(y, x) + .pi * 2 + .pi / 8) / (.pi / 4)) % 8 + 8) % 8
}
func tile(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ fill: NSColor, radius: CGFloat = 4) {
    fill.setFill()
    NSBezierPath(roundedRect: NSRect(x: x-size/2, y: y-size/2, width: size, height: size), xRadius: radius, yRadius: radius).fill()
}
func motif(_ option: Int, template: Bool = false, ink: NSColor = .black) {
    func shade(_ index: Int, level: CGFloat = 1) -> NSColor {
        if template { return ink }
        return color(palette[(index + 8) % 8]).blended(withFraction: 1-level, of: .white)!
    }
    switch option {
    case 0:
        for y in -5...5 { for x in -5...5 {
            let ring = abs(x)+abs(y)
            guard ring <= 5, ring >= 2 else { continue }
            if template && ring != 5 && ring != 2 { continue }
            tile(CGFloat(x)*67, CGFloat(y)*67, template ? 56 : 59,
                 shade(sector(CGFloat(x), CGFloat(y)), level: ring == 2 ? 0.62 : ring == 3 ? 0.8 : 1))
        }}
        tile(0, 0, 69, template ? ink : color(0x28345C), radius: 7)
        if !template { tile(0, 0, 29, .white, radius: 2) }
    case 1:
        for i in 0..<8 {
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform(); transform.rotate(byDegrees: CGFloat(i)*45); transform.concat()
            for (x,y,size,level) in [(0.0,145.0,62.0,0.6),(-36,218,64,0.86),(36,218,64,1),(0,291,64,1),(0,364,39,0.74)] {
                if template && y == 364 { continue }
                tile(x, y, size, shade(i, level: level), radius: template ? 4 : 6)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        tile(0,0,76,template ? ink : color(0xF2B635),radius: 10)
    case 2:
        for i in 0..<4 {
            NSGraphicsContext.saveGraphicsState()
            let transform=NSAffineTransform(); transform.rotate(byDegrees: CGFloat(i)*90); transform.concat()
            for (j,p) in [(1,4),(2,4),(3,4),(4,4),(4,3),(4,2),(4,1),(3,1),(2,1)].enumerated() {
                tile(CGFloat(p.0)*72-36,CGFloat(p.1)*72-36,64,shade(i*2 + (j>4 ? 1 : 0)),radius: 5)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        tile(0,0,72,template ? ink : color(0xF4B54A),radius: 5)
    case 3:
        for i in 0..<8 {
            NSGraphicsContext.saveGraphicsState()
            let transform=NSAffineTransform(); transform.rotate(byDegrees: CGFloat(i)*45); transform.concat()
            tile(0,268,105,shade(i),radius: 12)
            tile(0,143,80,shade(i,level: 0.65),radius: 10)
            NSGraphicsContext.restoreGraphicsState()
        }
        tile(0,0,78,template ? ink : color(0x2C3763),radius: 12)
        if !template { tile(0,0,34,.white,radius: 3) }
    case 4:
        for y in -4...4 { for x in -4...4 {
            let ring=max(abs(x),abs(y))
            guard ring > 0, !(abs(x)==4 && abs(y)==4) else { continue }
            if template && ring != 4 && ring != 1 { continue }
            let angle=sector(CGFloat(x),CGFloat(y))
            tile(CGFloat(x)*78,CGFloat(y)*78,68,shade(angle,level: CGFloat(ring)*0.19+0.22),radius: 8)
        }}
        tile(0,0,61,template ? ink : color(0x29324B),radius: 6)
        if !template { tile(0,0,25,.white,radius: 1) }
    default:
        for y in -5...5 { for x in -5...5 {
            let ax=abs(x), ay=abs(y), ring=max(ax,ay)
            let visible = (ax+ay<=5 && ax+ay>=2) || (ax==ay && ax<=3)
            guard visible else {continue}
            if template && ax+ay<4 && ring>1 {continue}
            tile(CGFloat(x)*66,CGFloat(y)*66,58,shade(sector(CGFloat(x),CGFloat(y)),level: ring>2 ? 1 : 0.65),radius: 2)
        }}
        tile(0,0,65,template ? ink : color(0xF2B135),radius: 3)
    }
}
func bitmap(width: Int, height: Int, draw: () -> Void) -> NSBitmapImageRep {
    let b=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:b)
    draw(); NSGraphicsContext.restoreGraphicsState(); return b
}
func icon(_ option: Int, size: Int, template: Bool = false) -> NSBitmapImageRep {
    bitmap(width:size,height:size) {
        let c=NSGraphicsContext.current!.cgContext; c.scaleBy(x:CGFloat(size)/1024,y:CGFloat(size)/1024)
        if !template {
            color(0xFAFAF7).setFill()
            NSBezierPath(roundedRect:NSRect(x:52,y:52,width:920,height:920),xRadius:205,yRadius:205).fill()
        }
        c.translateBy(x:512,y:512)
        if template {c.scaleBy(x:1.27,y:1.27)}
        motif(option,template:template)
    }
}
func write(_ image:NSBitmapImageRep,_ name:String) throws {
    try image.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name))
}
if let flag = CommandLine.arguments.firstIndex(of: "--package"), CommandLine.arguments.count > flag + 1,
   let number = Int(CommandLine.arguments[flag + 1]), (1...6).contains(number) {
    let selected = number - 1
    let iconset = output.appendingPathComponent("Rangoli.iconset", isDirectory: true)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        for multiplier in [1, 2] {
            let suffix = multiplier == 2 ? "@2x" : ""
            let image = icon(selected, size: points * multiplier)
            try image.representation(using: .png, properties: [:])!.write(
                to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
        }
    }
    try write(icon(selected, size: 1024), "Rangoli-Icon.png")
    try write(icon(selected, size: 18, template: true), "RangoliMenu.png")
    try write(icon(selected, size: 36, template: true), "RangoliMenu@2x.png")
    exit(EXIT_SUCCESS)
}
for i in 0..<6 {
    for size in [16,32,128,256,512,1024] {try write(icon(i,size:size),"option-\(i+1)-\(size).png")}
    try write(icon(i,size:18,template:true),"option-\(i+1)-menu.png")
    try write(icon(i,size:36,template:true),"option-\(i+1)-menu@2x.png")
}
func text(_ value:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ weight:NSFont.Weight = .regular,_ ink:NSColor = .labelColor) {
    (value as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:ink])
}
let board=bitmap(width:1232,height:1000) {
    color(0xF0F1F4).setFill(); NSRect(x:0,y:0,width:1232,height:1000).fill()
    text("Rangoli",28,943,32,.semibold,color(0x252B3B))
    text("Six pixel-inspired directions · App icon + matching menu bar symbol",29,915,16,.regular,color(0x626A7B))
    for i in 0..<6 {
        let x:CGFloat=24+CGFloat(i%3)*400, y:CGFloat=i<3 ? 487 : 69
        color(0xFFFFFF).setFill(); NSBezierPath(roundedRect:NSRect(x:x,y:y,width:384,height:398),xRadius:24,yRadius:24).fill()
        let app=NSImage(size:NSSize(width:1024,height:1024)); app.addRepresentation(icon(i,size:512))
        app.draw(in:NSRect(x:x+88,y:y+156,width:208,height:208))
        text("\(i+1)  \(titles[i])",x+24,y+119,22,.semibold,color(0x252B3B))
        text(descriptions[i],x+24,y+95,13,.regular,color(0x626A7B))
        text("MENU BAR",x+24,y+38,10,.semibold,color(0x7F8491))
        for (j,bg) in [UInt32(0xEFF1F5),UInt32(0x303542)].enumerated() {
            let rect=NSRect(x:x+111+CGFloat(j)*122,y:y+25,width:110,height:37)
            color(bg).setFill(); NSBezierPath(roundedRect:rect,xRadius:10,yRadius:10).fill()
            NSGraphicsContext.saveGraphicsState()
            let c=NSGraphicsContext.current!.cgContext
            c.translateBy(x:rect.midX,y:rect.midY); c.scaleBy(x:18/800,y:18/800)
            motif(i,template:true,ink:j==0 ? color(0x454A57) : .white)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
    text("Each symbol is simplified for an 18 pt menu bar; the app artwork is rendered at every required size.",28,26,13,.regular,color(0x747C8B))
}
try write(board,"Rangoli-icon-options.png")
print(output.appendingPathComponent("Rangoli-icon-options.png").path)
