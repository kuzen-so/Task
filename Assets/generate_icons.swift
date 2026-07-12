import AppKit

// 生成状态栏图标：白色圆角方块，两个黑色圆点眼睛
func generateStatusBarIcon() {
    let size = NSSize(width: 72, height: 72)
    let cornerRadius: CGFloat = 16

    let image = NSImage(size: size, flipped: false) { rect in
        NSColor.white.setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.fill()

        let eyeSize = NSSize(width: 10, height: 10)
        NSColor.black.setFill()
        let leftEye = NSBezierPath(ovalIn: NSRect(
            x: rect.midX - 16 - eyeSize.width / 2,
            y: rect.midY - eyeSize.height / 2,
            width: eyeSize.width,
            height: eyeSize.height
        ))
        leftEye.fill()

        let rightEye = NSBezierPath(ovalIn: NSRect(
            x: rect.midX + 16 - eyeSize.width / 2,
            y: rect.midY - eyeSize.height / 2,
            width: eyeSize.width,
            height: eyeSize.height
        ))
        rightEye.fill()

        return true
    }

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to generate statusbar_icon.png")
        exit(1)
    }

    try? data.write(to: URL(fileURLWithPath: "Assets/statusbar_icon.png"))
    print("Generated Assets/statusbar_icon.png")
}

// 生成 AppIcon.icns：多个尺寸拼接
func generateAppIcon() {
    let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]
    let iconImages: [NSImageRep] = sizes.compactMap { size in
        generateAppIconImage(size: CGSize(width: size, height: size))?.representations.first
    }

    let iconSet = NSImage()
    iconImages.forEach { iconSet.addRepresentation($0) }

    let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

    let iconsetDir = workDir.appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

    for size in sizes {
        guard let image = generateAppIconImage(size: CGSize(width: size, height: size)),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { continue }

        let name = "icon_\(size)x\(size).png"
        try? pngData.write(to: iconsetDir.appendingPathComponent(name))

        if size <= 512 {
            let retinaName = "icon_\(size)x\(size)@2x.png"
            let retinaSize = CGSize(width: size * 2, height: size * 2)
            if let retinaImage = generateAppIconImage(size: retinaSize),
               let retinaTiff = retinaImage.tiffRepresentation,
               let retinaBitmap = NSBitmapImageRep(data: retinaTiff),
               let retinaData = retinaBitmap.representation(using: .png, properties: [:]) {
                try? retinaData.write(to: iconsetDir.appendingPathComponent(retinaName))
            }
        }
    }

    let task = Process()
    task.launchPath = "/usr/bin/iconutil"
    task.arguments = ["-c", "icns", iconsetDir.path, "-o", "Assets/AppIcon.icns"]
    task.launch()
    task.waitUntilExit()

    try? FileManager.default.removeItem(at: workDir)
    print("Generated Assets/AppIcon.icns")
}

func generateAppIconImage(size: CGSize) -> NSImage? {
    let cornerRadius = size.width * 0.22
    let image = NSImage(size: size, flipped: false) { rect in
        NSColor.white.setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.fill()

        let eyeSize = CGSize(width: size.width * 0.12, height: size.width * 0.12)
        NSColor.black.setFill()
        let leftEye = NSBezierPath(ovalIn: NSRect(
            x: rect.midX - size.width * 0.22 - eyeSize.width / 2,
            y: rect.midY - eyeSize.height / 2,
            width: eyeSize.width,
            height: eyeSize.height
        ))
        leftEye.fill()

        let rightEye = NSBezierPath(ovalIn: NSRect(
            x: rect.midX + size.width * 0.22 - eyeSize.width / 2,
            y: rect.midY - eyeSize.height / 2,
            width: eyeSize.width,
            height: eyeSize.height
        ))
        rightEye.fill()

        return true
    }
    return image
}

generateStatusBarIcon()
generateAppIcon()
