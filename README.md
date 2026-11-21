# R-Cleaner

**R-Cleaner** is a native macOS system care, cleanup, protection, performance, and storage intelligence suite developed by `resitdc` in SwiftUI + AppKit.

## Complete Feature Suite

1. **Smart Care** — Unified 5-pillar scan (Cleanup, Protection, Performance, Applications, My Clutter) with live status tiles, deep review jump links, and single-click optimization.
2. **Cleanup** — System Junk (User & System Caches, Logs, Xcode DerivedData/Simulators, Broken Preferences, Broken Login Items, iOS Backups, Deleted Users), Mail Attachments, Trash Bins (System & Mounted Volumes), and **AI Clutter** (Claude, Codex, Gemini/Antigravity, Cursor caches/logs + Ollama/LM Studio/HuggingFace local models).
3. **Protection** — Malware Removal (Quick / Balanced / Deep scan modes across LaunchAgents, LaunchDaemons, Downloads & Applications + Real-Time Monitor toggle), Privacy Check (Safari, Chrome, Firefox, Recent Items, Wi-Fi Networks), and Application Permissions (macOS TCC audit).
4. **Performance** — 8 Maintenance Tasks (Free Up RAM, Flush DNS Cache, Free Up Purgeable Space, Thin Time Machine Snapshots, Reindex Spotlight, Run Periodic Scripts, Speed Up Mail, Repair Disk Permissions) + Login Items & Background Items (Launch Agents/Daemons) manager.
5. **Applications** — Full App Uninstaller with related-file discovery (Preferences, Supporting Files, Caches, Logs, Containers, Audio Plugins) & Reset App, App Updater (Sparkle appcasts & macOS Software Update), App Leftovers, and Unused Installers (DMG/PKG).
6. **My Clutter** — Exact SHA-256 Duplicate Finder with Smart Selection, Similar Images detector with Blur visual-flaw detection & Best-to-Keep badges, Large & Old Files filterable by Size/Kind, and Downloads organizer.
7. **Space Lens** — Interactive proportional bubble storage visualizer with directory drill-down, breadcrumbs, hidden files, cloud indicators, and purgeable space readout.
8. **Cloud Cleanup** — Discovers and scans iCloud Drive, Google Drive, OneDrive, and Dropbox local/synced storage with **Unsync (Evict Local Copy)** and Remove.
9. **Email Cleanup** — Local Apple Mail `.emlx` analyzer categorizing Smart Cleanup suggestions, Newsletters & Promotions, Subscriptions, Senders, Drafts, and Spam with Email Preview.
10. **My Tools** — Searchable quick-launch toolbox with Favorites and direct focused flows.
11. **Screen Cleaning Mode** — Full-screen dark cleaning surface with optional Accessibility keyboard/trackpad lock and safe `Esc` exit.
12. **Built-in Voice AI System** — Bundled offline studio British male neural voice pack (`27` clips) with real-time `AVAudioEngine` HUD EQ, ambience, chime, and live modular system briefings (zero downloads required).
13. **Assistant & My Activity** — Real-time Mac Health Score (0–100), dynamic Recommendations popover, and persistent Activity Statistics dashboard.
14. **R-Cleaner Menu Bar Monitor** — Always-available `MenuBarExtra` satellite dashboard showing live Storage, Protection, Memory (+ Free Up + Top Consumers), CPU (+ Uptime + Top Consumers), Battery (Cycles & Health), Network (+ Live Speed & Speed Test), and External Drives (+ Eject).
15. **Settings** — 7-tab Preferences for General, Voice AI, Scanning, Protection, Categorized Ignore List, Menu, and Notifications.

## Local Build, Test & Packaging

```bash
# Run unit tests
swift test

# Build & package native R-Cleaner.app bundle
chmod +x scripts/build_app.sh scripts/build_dmg.sh
./scripts/build_app.sh release

# Build Universal (Apple Silicon + Intel) .app, .dmg, and .app.zip with SHA-256 checksums
UNIVERSAL=1 APP_VERSION=1.0.0 ./scripts/build_app.sh release
UNIVERSAL=1 APP_VERSION=1.0.0 ./scripts/build_dmg.sh

# Launch R-Cleaner.app
open dist/R-Cleaner.app
```

## GitHub Actions CI/CD

- **CI (`.github/workflows/ci.yml`)**: Automatically runs `swift test`, builds a Universal (`arm64` + `x86_64`) `R-Cleaner.app`, packages both `.dmg` and `.app.zip`, and uploads downloadable artifacts on every push or PR to `main`.
- **Release (`.github/workflows/release.yml`)**: Triggered automatically when pushing a version tag (e.g., `git tag v1.0.0 && git push origin v1.0.0`) or manually from the **Actions** tab. Publishes a GitHub Release with `R-Cleaner-<version>-universal.dmg`, `R-Cleaner-<version>-universal.app.zip`, and `SHA256SUMS.txt`.
  - Works out of the box with ad-hoc signing.
  - Optionally supports Apple Developer ID signing and notarization by adding these repository secrets: `MACOS_CERTIFICATE_P12` (base64 `.p12`), `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID`.
