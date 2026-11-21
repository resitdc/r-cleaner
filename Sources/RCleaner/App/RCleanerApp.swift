import SwiftUI
import AppKit

public final class RCleanerAppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep Menu Bar Monitor alive when main window closes
    }
}

@main
public struct RCleanerApp: App {
    @NSApplicationDelegateAdaptor(RCleanerAppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    public init() {}

    public var body: some Scene {
        WindowGroup("R-Cleaner") {
            MainWindowView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1140, height: 740)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About R-Cleaner") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "R-Cleaner",
                        .applicationVersion: "1.0.0",
                        .credits: NSAttributedString(string: "Native macOS System Care, Cleanup, Protection & Performance Suite.")
                    ])
                }
            }
            CommandGroup(after: .appSettings) {
                Button("Settings...") {
                    appState.showSettingsWindow = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("Care") {
                Button("Run Smart Care") {
                    appState.selectedModule = .smartCare
                    appState.startSmartCareScan()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Free Up RAM") {
                    appState.quickFreeUpRAM()
                }

                Button("Empty Trash") {
                    appState.quickEmptyTrash()
                }

                Divider()

                Button("Screen Cleaning Mode") {
                    appState.launchScreenCleaningMode()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Replay Intro Animation & Tour") {
                    appState.replayIntro()
                }
            }
        }

        // Integrated Menu Bar Monitor (deduplicated binding avoids macOS 15 KVO feedback loop)
        MenuBarExtra(isInserted: Binding(
            get: { appState.settings.enableMenuMonitor },
            set: { newValue in
                if appState.settings.enableMenuMonitor != newValue {
                    appState.settings.enableMenuMonitor = newValue
                }
            }
        )) {
            MenuBarMonitorView()
                .environmentObject(appState)
        } label: {
            Image(systemName: "sparkles.rectangle.stack.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 780, height: 540)
        }
    }
}
