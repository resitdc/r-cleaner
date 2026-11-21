import SwiftUI
import AppKit

/// Animated Intro & Onboarding Flow featuring a choreographed 60fps Canvas reveal
/// of the `resitdc` logo, interactive feature carousel, and Full Disk Access setup.
public struct IntroFlowView: View {
    @EnvironmentObject var appState: AppState

    enum IntroStage: Equatable {
        case cinematicReveal
        case carousel
        case permissions
    }

    struct CarouselSlide: Identifiable {
        let id: Int
        let tag: String
        let title: String
        let subtitle: String
        let icon: String
        let accent: Color
        let secondary: Color
        let highlights: [String]
    }

    @State private var stage: IntroStage = .cinematicReveal
    @State private var startDate = Date()
    @State private var strokeProgress: CGFloat = 0
    @State private var fillOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.86
    @State private var logoTilt: Double = 18
    @State private var shineOffset: CGFloat = -220
    @State private var textReveal: Bool = false
    @State private var shockwaveScale: CGFloat = 0.55
    @State private var shockwaveOpacity: Double = 0
    @State private var currentSlide: Int = 0
    @State private var hasAutoAdvanced = false

    private let slides: [CarouselSlide] = [
        CarouselSlide(
            id: 0,
            tag: "SMART CARE",
            title: "All-in-one care for your Mac",
            subtitle: "Meet Smart Care — a 360° optimization routine that cleans, protects, speeds up, updates, and declutters your Mac in one smooth flow.",
            icon: "sparkles",
            accent: Color(hex: "19F8FF"),
            secondary: Color(hex: "7B61FF"),
            highlights: ["5-pillar parallel scan", "One-click optimization", "Full cleanup log"]
        ),
        CarouselSlide(
            id: 1,
            tag: "CLEANUP + AI CLUTTER",
            title: "Faster, deeper junk cleanup",
            subtitle: "Reclaim gigabytes from system caches, Xcode DerivedData, Trash bins, Mail attachments, and AI tool caches & local LLM models.",
            icon: "trash.circle.fill",
            accent: Color(hex: "FF4FD8"),
            secondary: Color(hex: "FF7A59"),
            highlights: ["System & Xcode Junk", "Claude, Cursor, Gemini caches", "Ollama & LM Studio models"]
        ),
        CarouselSlide(
            id: 2,
            tag: "PROTECTION",
            title: "Scan for malware & guard privacy",
            subtitle: "Detect persistence threats across 18 malware categories, wipe browser traces, and audit macOS app permissions.",
            icon: "shield.lefthalf.filled.badge.checkmark",
            accent: Color(hex: "2ED573"),
            secondary: Color(hex: "1BC6B4"),
            highlights: ["Quick, Balanced & Deep scans", "Safari, Chrome & Firefox cleanup", "TCC permission audit"]
        ),
        CarouselSlide(
            id: 3,
            tag: "APPS, CLUTTER & SPACE LENS",
            title: "Visualize storage & wipe duplicates",
            subtitle: "Uninstall apps completely with all leftovers, detect SHA-256 duplicate copies & blurry photos, and explore disk usage with interactive bubbles.",
            icon: "circle.hexagongrid.fill",
            accent: Color(hex: "00BBF9"),
            secondary: Color(hex: "9B5DE5"),
            highlights: ["Complete App Uninstaller", "Perceptual Similar Images", "Interactive Space Lens map"]
        ),
        CarouselSlide(
            id: 4,
            tag: "MENU MONITOR & SCREEN CARE",
            title: "Monitor your Mac with ease",
            subtitle: "Live CPU, Memory, Battery, Network Speed Test, and External Drives live right in your menu bar — plus Screen Cleaning Mode with keyboard lock.",
            icon: "gauge.with.dots.needle.67percent",
            accent: Color(hex: "FF9F43"),
            secondary: Color(hex: "36E2F8"),
            highlights: ["Real-time Menu Bar satellite", "Mac Health Score & Assistant", "Screen Cleaning Mode"]
        )
    ]

    public init() {}

    public var body: some View {
        ZStack {
            // Animated cosmic GPU Canvas backdrop (active ONLY while IntroFlowView is mounted)
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                IntroCosmicCanvas(
                    elapsed: timeline.date.timeIntervalSince(startDate),
                    accentColor: activeAccent,
                    secondaryColor: activeSecondary
                )
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Top bar with subtle resitdc brand + Skip button
                HStack {
                    HStack(spacing: 9) {
                        ResitdcLogoMark(height: 18, glow: true)
                        Text("R-Cleaner")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .opacity(stage == .cinematicReveal ? (textReveal ? 0.85 : 0) : 0.95)

                    Spacer()

                    Button("Skip Intro") {
                        appState.completeIntro(startSmartCare: false)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)

                Spacer()

                Group {
                    switch stage {
                    case .cinematicReveal:
                        cinematicLogoRevealStage
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    case .carousel:
                        carouselStage
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity.combined(with: .move(edge: .leading))
                            ))
                    case .permissions:
                        fullDiskAccessStage
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .trailing)),
                                removal: .opacity
                            ))
                    }
                }

                Spacer()
            }
        }
        .onAppear {
            startDate = Date()
            runCinematicChoreography()
        }
    }

    private var activeAccent: Color {
        switch stage {
        case .cinematicReveal: return Color(hex: "19F8FF")
        case .carousel: return slides[currentSlide].accent
        case .permissions: return Color(hex: "2ED573")
        }
    }

    private var activeSecondary: Color {
        switch stage {
        case .cinematicReveal: return Color(hex: "7B61FF")
        case .carousel: return slides[currentSlide].secondary
        case .permissions: return Color(hex: "19F8FF")
        }
    }

    // MARK: - Stage 1: Cinematic resitdc.svg Logo Animation

    private var cinematicLogoRevealStage: some View {
        VStack(spacing: 28) {
            ZStack {
                // Expanding neon shockwave ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "19F8FF"), Color(hex: "FF4FD8"), Color(hex: "7B61FF")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.5
                    )
                    .frame(width: 240, height: 240)
                    .scaleEffect(shockwaveScale)
                    .opacity(shockwaveOpacity)

                // Ambient halo behind logo (clean & frameless, no box)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "19F8FF").opacity(0.32 * fillOpacity), Color(hex: "7B61FF").opacity(0.14 * fillOpacity), .clear],
                            center: .center,
                            startRadius: 15,
                            endRadius: 185
                        )
                    )
                    .frame(width: 370, height: 370)

                // The exact resitdc.svg interlocking paths (true 130:93 aspect ratio): wireframe draw -> luminous fill -> light wipe
                ZStack {
                    // Neon wireframe stroke draw
                    ResitdcCyanShape()
                        .trim(from: 0, to: strokeProgress)
                        .stroke(Color(hex: "19F8FF"), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .shadow(color: Color(hex: "19F8FF"), radius: 10)

                    ResitdcWhiteShape()
                        .trim(from: 0, to: strokeProgress)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .shadow(color: Color.white.opacity(0.8), radius: 8)

                    // Solid luminous vector fill
                    ResitdcCyanShape()
                        .fill(Color(hex: "19F8FF"))
                        .opacity(fillOpacity)
                        .shadow(color: Color(hex: "19F8FF").opacity(0.65), radius: 18)

                    ResitdcWhiteShape()
                        .fill(Color.white)
                        .opacity(fillOpacity)
                        .shadow(color: Color.white.opacity(0.45), radius: 10)
                }
                .overlay {
                    // Glossy diagonal light-wipe sheen applied as overlay so it never distorts logo bounds
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.75), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 64, height: 220)
                        .rotationEffect(.degrees(22))
                        .offset(x: shineOffset)
                        .mask {
                            ZStack {
                                ResitdcCyanShape().fill(.white)
                                ResitdcWhiteShape().fill(.white)
                            }
                            .frame(width: 224, height: 160)
                        }
                        .opacity(fillOpacity)
                }
                .frame(width: 224, height: 160)
                .scaleEffect(logoScale)
                .rotation3DEffect(.degrees(logoTilt), axis: (x: 0.35, y: 1, z: 0))
            }

            VStack(spacing: 10) {
                Text("Welcome to R-Cleaner")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(hex: "19F8FF")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("Developed by resitdc  •  Keep your Mac clean, fast, and protected")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .opacity(textReveal ? 1 : 0)
            .offset(y: textReveal ? 0 : 18)

            HStack(spacing: 14) {
                Button {
                    hasAutoAdvanced = true
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        stage = .carousel
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("Take a Tour")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color(hex: "19F8FF"), Color(hex: "6BF2C2")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    )
                    .shadow(color: Color(hex: "19F8FF").opacity(0.45), radius: 14, y: 4)
                }
                .buttonStyle(.plain)

                Button {
                    hasAutoAdvanced = true
                    appState.completeIntro(startSmartCare: true)
                } label: {
                    Text("Start Your First Scan")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.24), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .opacity(textReveal ? 1 : 0)
            .offset(y: textReveal ? 0 : 12)
        }
    }

    // MARK: - Stage 2: Interactive Feature Carousel

    private var carouselStage: some View {
        let slide = slides[currentSlide]

        return VStack(spacing: 28) {
            HStack(spacing: 48) {
                // Left text block
                VStack(alignment: .leading, spacing: 16) {
                    Text(slide.tag)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(slide.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(slide.accent.opacity(0.16)))

                    Text(slide.title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(slide.subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(4)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(slide.highlights, id: \.self) { point in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(slide.accent)
                                Text(point)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.92))
                            }
                        }
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: 440, alignment: .leading)
                .id(slide.id)
                .transition(.opacity.combined(with: .offset(x: 16)))

                // Right animated floating glass emblem + resitdc corner stamp
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [slide.accent.opacity(0.36), slide.secondary.opacity(0.14), .clear],
                                center: .center,
                                startRadius: 15,
                                endRadius: 145
                            )
                        )
                        .frame(width: 280, height: 280)

                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 220, height: 220)
                        .overlay(
                            RoundedRectangle(cornerRadius: 36, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(colors: [slide.accent.opacity(0.7), slide.secondary.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 1.8
                                )
                        )
                        .shadow(color: slide.accent.opacity(0.32), radius: 24, y: 10)

                    Image(systemName: slide.icon)
                        .font(.system(size: 82, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(colors: [.white, slide.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: slide.accent.opacity(0.55), radius: 14)

                    // Frameless resitdc mark floating at bottom-right
                    ResitdcLogoMark(height: 26, glow: true)
                        .offset(x: 84, y: 84)
                }
                .id("art-\(slide.id)")
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            }
            .padding(.horizontal, 48)

            // Pagination Dots & Controls
            HStack(spacing: 20) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        if currentSlide > 0 {
                            currentSlide -= 1
                        } else {
                            stage = .cinematicReveal
                        }
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    ForEach(slides) { s in
                        Capsule()
                            .fill(s.id == currentSlide ? slide.accent : Color.white.opacity(0.25))
                            .frame(width: s.id == currentSlide ? 26 : 8, height: 8)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    currentSlide = s.id
                                }
                            }
                    }
                }

                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) {
                        if currentSlide < slides.count - 1 {
                            currentSlide += 1
                        } else {
                            stage = .permissions
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(currentSlide < slides.count - 1 ? "Next" : "Continue")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(slide.accent))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Stage 3: Full Disk Access Prompt

    private var fullDiskAccessStage: some View {
        let granted = FileSystemHelpers.hasFullDiskAccess()

        return VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: "2ED573").opacity(0.32), .clear], center: .center, startRadius: 15, endRadius: 95))
                    .frame(width: 180, height: 180)
                ResitdcLogoMark(height: 76, glow: true)
                Image(systemName: granted ? "checkmark.seal.fill" : "lock.shield.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(granted ? Color(hex: "2ED573") : Color(hex: "19F8FF"))
                    .offset(x: 52, y: 36)
            }

            VStack(spacing: 8) {
                Text(granted ? "Full Disk Access Granted!" : "Grant Full Disk Access")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(granted
                     ? "Enjoy R-Cleaner's full potential with deeper cleaning, better Mac performance, and complete storage visibility."
                     : "Allow R-Cleaner to find and remove hidden system junk, Safari & Mail traces, and large unused files.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            // 3 FDA Benefit Tags
            HStack(spacing: 12) {
                fdaTag(icon: "shield.checkmark.fill", text: "Get full protection")
                fdaTag(icon: "sparkles", text: "Find 27.5% more junk")
                fdaTag(icon: "folder.fill", text: "Manage all your files")
            }

            HStack(spacing: 14) {
                if !granted {
                    Button {
                        FileSystemHelpers.openPrivacySettings(pane: "Privacy_AllFiles")
                    } label: {
                        Text("Grant Full Disk Access")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color(hex: "19F8FF")))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    appState.completeIntro(startSmartCare: true)
                } label: {
                    Text("Start Your First Scan")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(granted ? .black : .white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(granted ? Color(hex: "2ED573") : Color.white.opacity(0.16)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.24), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button("Enter R-Cleaner") {
                    appState.completeIntro(startSmartCare: false)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 40)
    }

    private func fdaTag(icon: String, text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).foregroundStyle(Color(hex: "19F8FF"))
            Text(text).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(0.09)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
    }

    // MARK: - Choreographed Intro Timing

    private func runCinematicChoreography() {
        strokeProgress = 0
        fillOpacity = 0
        logoScale = 0.86
        logoTilt = 18
        shineOffset = -220
        textReveal = false
        shockwaveScale = 0.55
        shockwaveOpacity = 0

        // Beat 1: Wireframe stroke draws the resitdc interlocking hexagon paths
        withAnimation(.easeInOut(duration: 1.05)) {
            strokeProgress = 1.0
        }

        // Beat 2: Fill blooms + 3D spring settle + shockwave pulse
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.90) {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.72)) {
                fillOpacity = 1.0
                logoScale = 1.0
                logoTilt = 0
            }
            shockwaveOpacity = 0.85
            withAnimation(.easeOut(duration: 1.15)) {
                shockwaveScale = 1.95
                shockwaveOpacity = 0
            }
        }

        // Beat 3: Glossy wipe sheen + title & buttons rise in
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) {
            withAnimation(.easeInOut(duration: 0.85)) {
                shineOffset = 220
            }
            withAnimation(.spring(response: 0.65, dampingFraction: 0.82)) {
                textReveal = true
            }
            if appState.settings.playSounds {
                NSSound(named: NSSound.Name("Purr"))?.play()
            }
        }
    }
}

// MARK: - GPU-Accelerated Cosmic Ribbon & Starlight Canvas

private struct IntroCosmicCanvas: View {
    let elapsed: TimeInterval
    let accentColor: Color
    let secondaryColor: Color

    var body: some View {
        Canvas { ctx, size in
            let t = elapsed

            // Deep cosmic base gradient
            let bgRect = CGRect(origin: .zero, size: size)
            ctx.fill(
                Path(bgRect),
                with: .linearGradient(
                    Gradient(colors: [Color(hex: "090D1C"), Color(hex: "140D2A"), Color(hex: "070A14")]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )

            // Orbiting aurora light orbs
            let orb1 = CGPoint(
                x: size.width * (0.28 + 0.14 * cos(t * 0.55)),
                y: size.height * (0.28 + 0.10 * sin(t * 0.45))
            )
            let orb2 = CGPoint(
                x: size.width * (0.72 + 0.14 * sin(t * 0.48)),
                y: size.height * (0.72 + 0.10 * cos(t * 0.40))
            )
            let r1 = max(size.width, size.height) * 0.48
            ctx.fill(
                Path(ellipseIn: CGRect(x: orb1.x - r1, y: orb1.y - r1, width: r1 * 2, height: r1 * 2)),
                with: .radialGradient(
                    Gradient(colors: [accentColor.opacity(0.28), .clear]),
                    center: orb1,
                    startRadius: 10,
                    endRadius: r1
                )
            )
            let r2 = max(size.width, size.height) * 0.44
            ctx.fill(
                Path(ellipseIn: CGRect(x: orb2.x - r2, y: orb2.y - r2, width: r2 * 2, height: r2 * 2)),
                with: .radialGradient(
                    Gradient(colors: [secondaryColor.opacity(0.26), .clear]),
                    center: orb2,
                    startRadius: 10,
                    endRadius: r2
                )
            )

            // Flowing energy ribbons across the canvas
            for wave in 0..<3 {
                var path = Path()
                let baseY = size.height * (0.32 + Double(wave) * 0.18)
                let amp = 26.0 + Double(wave) * 14.0
                let speed = 0.9 + Double(wave) * 0.35
                path.move(to: CGPoint(x: 0, y: baseY))
                for step in stride(from: 0.0, through: Double(size.width), by: 24.0) {
                    let nx = step / max(1.0, Double(size.width))
                    let y = baseY + sin(nx * .pi * 2.4 + t * speed + Double(wave)) * amp
                    path.addLine(to: CGPoint(x: step, y: y))
                }
                ctx.stroke(
                    path,
                    with: .color((wave % 2 == 0 ? accentColor : secondaryColor).opacity(0.11)),
                    lineWidth: 1.5
                )
            }

            // Subtle drifting starlight particles
            for i in 0..<36 {
                let seed = Double(i) * 1.6180339
                let px = ((seed * 317.3 + t * (12.0 + Double(i % 5) * 4.0)).truncatingRemainder(dividingBy: max(1, Double(size.width))))
                let py = ((seed * 521.7 + sin(t * 0.6 + seed) * 28.0).truncatingRemainder(dividingBy: max(1, Double(size.height))))
                let x = px < 0 ? px + Double(size.width) : px
                let y = py < 0 ? py + Double(size.height) : py
                let alpha = 0.18 + 0.30 * (0.5 + 0.5 * sin(t * 1.8 + seed * 3.0))
                let dotR = 1.2 + Double(i % 3) * 0.8
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: dotR * 2, height: dotR * 2)),
                    with: .color((i % 3 == 0 ? accentColor : .white).opacity(alpha))
                )
            }
        }
    }
}
