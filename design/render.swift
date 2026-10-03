// Regenerates the app icon, DMG background and README hero image.
// Run from the repo root: swift design/render.swift
import AppKit
import SwiftUI

let out = "design"
let joinBlue = Color(red: 0.04, green: 0.52, blue: 1.0)

@MainActor func save(_ view: some View, _ path: String, scale: CGFloat = 1) {
    let r = ImageRenderer(content: view.environment(\.colorScheme, .light))
    r.scale = scale
    guard let cg = r.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { fatalError("render failed: \(path)") }
    try! png.write(to: URL(fileURLWithPath: "\(out)/\(path)"))
    print("wrote \(out)/\(path) (\(cg.width)x\(cg.height))")
}

// MARK: Icon — 824pt squircle on a 1024 canvas (Apple's macOS template), white bell on blue.

struct Icon: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 185, style: .continuous)
        ZStack {
            shape
                .fill(LinearGradient(colors: [Color(red: 0.40, green: 0.72, blue: 1.0), Color(red: 0.0, green: 0.42, blue: 0.95)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(shape.strokeBorder(.white.opacity(0.22), lineWidth: 3))
                .shadow(color: .black.opacity(0.28), radius: 18, y: 12)
            Image(systemName: "bell.fill")
                .font(.system(size: 440, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .top, endPoint: .bottom))
                .rotationEffect(.degrees(-12))
                .shadow(color: Color(red: 0, green: 0.2, blue: 0.5).opacity(0.35), radius: 16, y: 10)
                .offset(x: 18, y: 0)
            Circle()
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.2), Color(red: 1, green: 0.42, blue: 0.1)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(.white, lineWidth: 14))
                .frame(width: 170, height: 170)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                .offset(x: 200, y: -190)
        }
        .frame(width: 824, height: 824)
        .frame(width: 1024, height: 1024)
    }
}

// MARK: DMG background — window 660x400, app icon at (165,185), Applications at (495,185).

struct DMGBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.white, Color(red: 0.93, green: 0.95, blue: 0.98)], startPoint: .top, endPoint: .bottom)
            Path { p in
                p.move(to: CGPoint(x: 276, y: 185)); p.addLine(to: CGPoint(x: 384, y: 185))
                p.move(to: CGPoint(x: 372, y: 174)); p.addLine(to: CGPoint(x: 385, y: 185)); p.addLine(to: CGPoint(x: 372, y: 196))
            }
            .stroke(joinBlue.opacity(0.55), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            Text("Drag HeadsUp to Applications")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(white: 0.45))
                .position(x: 330, y: 335)
        }
        .frame(width: 660, height: 400)
    }
}

// MARK: Hero — the alert on a neutral frosted wallpaper, approximating the real Liquid Glass design.

struct Wallpaper: View {
    var body: some View {
        ZStack {
            Color(red: 0.90, green: 0.91, blue: 0.93)
            blob(Color(red: 0.45, green: 0.66, blue: 1.0), 900, 300, 220)
            blob(Color(red: 1.0, green: 0.72, blue: 0.55), 800, 1180, 160)
            blob(Color(red: 0.74, green: 0.66, blue: 1.0), 900, 1050, 800)
            blob(Color(red: 0.55, green: 0.86, blue: 0.76), 700, 260, 820)
        }
        .frame(width: 1440, height: 900)
        .clipped()
    }

    func blob(_ c: Color, _ size: CGFloat, _ x: CGFloat, _ y: CGFloat) -> some View {
        Circle().fill(c.opacity(0.75)).frame(width: size, height: size).position(x: x, y: y).blur(radius: 160)
    }
}

struct Glass: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.white.opacity(0.5), in: Capsule())
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white, .black.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }
}

struct Hero: View {
    let ink = Color(white: 0.12)
    let secondary = Color(white: 0.12).opacity(0.55)

    var body: some View {
        ZStack {
            Wallpaper()
            Color.white.opacity(0.45)
            VStack(spacing: 56) {
                VStack(spacing: 18) {
                    HStack(spacing: 7) {
                        Circle().fill(joinBlue).frame(width: 8, height: 8)
                        Text("Work")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.75))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(joinBlue.opacity(0.16), in: Capsule())

                    Text("Design Review").font(.system(size: 68, weight: .semibold)).tracking(-1.4).foregroundStyle(ink)
                    Text("Starts in 1 min").font(.system(size: 32, weight: .medium, design: .rounded)).foregroundStyle(secondary)
                    Label("2:00 – 2:30 PM", systemImage: "clock").font(.system(size: 15, weight: .medium)).foregroundStyle(secondary)

                    HStack(spacing: 10) {
                        Image(systemName: "video.fill")
                        Text("Join")
                        Text("↩").font(.system(size: 12, weight: .medium)).opacity(0.6).padding(.leading, 2)
                    }
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30).frame(height: 52)
                    .background(LinearGradient(colors: [Color(red: 0.36, green: 0.65, blue: 0.98), Color(red: 0.18, green: 0.5, blue: 0.93)],
                                               startPoint: .top, endPoint: .bottom), in: Capsule())
                    .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.6), Color(red: 0.1, green: 0.35, blue: 0.75).opacity(0.6)],
                                                                   startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .shadow(color: joinBlue.opacity(0.25), radius: 10, y: 4)
                    .padding(.top, 14)
                }

                HStack(spacing: 8) {
                    Text("Snooze").foregroundStyle(secondary).padding(.trailing, 4)
                    ForEach(["1 min", "5 min", "10 min", "Until start"], id: \.self) { pill(Text($0)) }
                    Spacer().frame(width: 24)
                    pill(HStack(spacing: 8) { Text("Dismiss"); Text("esc").font(.system(size: 12, weight: .medium)).opacity(0.5) })
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ink)
            }
        }
        .frame(width: 1440, height: 900)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    func pill(_ label: some View) -> some View {
        label.padding(.horizontal, 18).frame(height: 38).modifier(Glass())
    }
}

MainActor.assumeIsolated {
    save(Icon(), "AppIcon.png")
    save(DMGBackground(), "dmg-background.png")
    save(DMGBackground(), "dmg-background@2x.png", scale: 2)
    try? FileManager.default.createDirectory(atPath: "\(out)/screenshots", withIntermediateDirectories: true)
    save(Hero(), "screenshots/alert.png", scale: 2)
}
