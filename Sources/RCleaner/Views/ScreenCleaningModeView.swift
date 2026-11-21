import SwiftUI
import AppKit
import CoreGraphics

/// Borderless NSWindow subclass that can become key/main so Escape key presses are always received
/// even when macOS Accessibility permission is not granted.
private final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Full-screen Screen Cleaning Mode for R-Cleaner.
/// Dims the screen to a pure dark cleaning surface, optionally locks keyboard/mouse input
/// when Accessibility permission is granted, and allows safe exit via Cmd+Q or pressing Escape.
public final class ScreenCleaningWindowController {
    public static let shared = ScreenCleaningWindowController()

    private var overlayWindows: [NSWindow] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var completionHandler: (() -> Void)?

    private init() {}

    @MainActor
    public func present(onComplete: @escaping () -> Void) {
        dismiss()
        self.completionHandler = onComplete

        let hasAccessibility = FileSystemHelpers.hasAccessibilityPermission()
        if hasAccessibility {
            installEventTap()
        }

        // Local monitor so Escape or Cmd+W / Cmd+Q exits immediately
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 || (event.modifierFlags.contains(.command) && (event.charactersIgnoringModifiers?.lowercased() == "q" || event.charactersIgnoringModifiers?.lowercased() == "w")) {
                Task { @MainActor in self?.dismiss() }
                return nil
            }
            return nil // Absorb all other keystrokes while cleaning
        }

        // Global fallback monitor for Escape in case another app steals focus when Accessibility is off
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in self?.dismiss() }
            }
        }

        for screen in NSScreen.screens {
            let win = KeyableBorderlessWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            win.isReleasedWhenClosed = false
            win.level = .screenSaver
            win.backgroundColor = .black
            win.isOpaque = true
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            win.contentView = NSHostingView(
                rootView: ScreenCleaningOverlayView(
                    keyboardLocked: hasAccessibility,
                    onExit: { [weak self] in self?.dismiss() }
                )
            )
            win.makeKeyAndOrderFront(nil)
            overlayWindows.append(win)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    public func dismiss() {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
        if let gMonitor = globalKeyMonitor {
            NSEvent.removeMonitor(gMonitor)
            globalKeyMonitor = nil
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        for win in overlayWindows {
            win.contentView = nil
            win.orderOut(nil)
            win.close()
        }
        overlayWindows.removeAll()
        if let handler = completionHandler {
            completionHandler = nil
            handler()
        }
    }

    private func installEventTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = ScreenCleaningWindowController.shared.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                // Allow Escape (53) or Cmd+Q (12) to exit cleanly
                if keyCode == 53 || (keyCode == 12 && flags.contains(.maskCommand)) {
                    DispatchQueue.main.async {
                        ScreenCleaningWindowController.shared.dismiss()
                    }
                    return nil
                }
            }
            return nil // Block accidental taps while wiping keyboard
        }

        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) {
            self.eventTap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
}

private struct ScreenCleaningOverlayView: View {
    let keyboardLocked: Bool
    let onExit: () -> Void
    @State private var shimmerOffset: CGFloat = -300

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Subtle dark ambient shine
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.05), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .offset(x: shimmerOffset)
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 46))
                    .foregroundStyle(Color.white.opacity(0.28))

                Text("Screen Cleaning Mode")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.32))

                Text("Your screen is ready — wipe it clean and make it shine.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.24))

                if keyboardLocked {
                    Label("Keyboard locked against accidental taps", systemImage: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "2ED573").opacity(0.5))
                } else {
                    Button("Enable Accessibility to lock keyboard globally") {
                        onExit()
                        FileSystemHelpers.openPrivacySettings(pane: "Privacy_Accessibility")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .buttonStyle(.plain)
                }

                Button(action: onExit) {
                    Text("Press Esc (or Click Here) to Exit")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .padding(.top, 24)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) {
                shimmerOffset = 300
            }
        }
    }
}
