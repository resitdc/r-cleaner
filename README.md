<div align="center">

# R-Cleaner

**Native macOS System Care, Cleanup, Protection, Performance & Storage Intelligence Suite**  
*Built with SwiftUI + AppKit by `resitdc` — featuring a bundled Jarvis-inspired offline Voice AI*

<p>
  <strong>🇺🇸 English</strong> &nbsp;|&nbsp; <a href="README.id.md">🇮🇩 Bahasa Indonesia</a>
</p>

<p>
  <a href="https://github.com/resitdc/resitdc-mac-cleaner/releases/latest">
    <img src="https://img.shields.io/badge/Download_Latest_Release-.dmg_%2F_.app-00B4D8?style=for-the-badge&logo=apple&logoColor=white" alt="Download Latest Release" />
  </a>
</p>

<p>
  <a href="https://github.com/resitdc/resitdc-mac-cleaner/releases/latest">
    <img src="https://img.shields.io/github/v/release/resitdc/resitdc-mac-cleaner?style=flat-square&color=7B61FF&label=Latest%20Version" alt="Latest Release" />
  </a>
  <a href="https://github.com/resitdc/resitdc-mac-cleaner/actions/workflows/ci.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/resitdc/resitdc-mac-cleaner/ci.yml?branch=main&style=flat-square&label=CI%20Build" alt="CI Status" />
  </a>
  <img src="https://img.shields.io/badge/macOS-14.0%2B%20Universal%20(Apple%20Silicon%20%26%20Intel)-2ED573?style=flat-square&logo=apple" alt="macOS 14+ Universal" />
  <img src="https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.10" />
</p>

</div>

---

## Download & Installation

1. Click the **Download Latest Release** button above or visit the [GitHub Releases page](https://github.com/resitdc/resitdc-mac-cleaner/releases/latest).
2. Download **`R-Cleaner-<version>-universal.dmg`** (works natively on both **Apple Silicon M1/M2/M3/M4** and **Intel** Macs running macOS 14.0 Sonoma or newer).
3. Double-click the `.dmg` file and drag **R-Cleaner** into your **Applications** folder.
4. Open **R-Cleaner** from **Applications** or Spotlight (`⌘ Space`).

> [!WARNING]
> **First-Time Launch Warning (macOS Gatekeeper / "Apple could not verify R-Cleaner"):**  
> Because R-Cleaner is open-source and ad-hoc signed (without a paid Apple Developer ID notarization certificate), macOS will block the app the first time you open it. To approve and launch it safely:
>
> **Option A — System Settings (Recommended on macOS 15 Sequoia & newer):**
> 1. Try opening **R-Cleaner** from **Applications** once, then click **Done** (or **OK**) on the macOS warning dialog.
> 2. Open **System Settings** → **Privacy & Security**.
> 3. Scroll down to the **Security** section — you will see *"R-Cleaner was blocked to protect your Mac"*.
> 4. Click **Open Anyway**, enter your Mac password / Touch ID, and confirm **Open Anyway**.
>
> **Option B — One-Line Terminal Command:**
> ```bash
> xattr -cr /Applications/R-Cleaner.app
> ```

### Recommended macOS Permissions (Optional)
For complete scanning capabilities, you can grant permissions from **Settings → General → macOS System Permissions** inside R-Cleaner:
- **Full Disk Access** — Allows inspecting Safari, Apple Mail attachments, and protected system/app caches.
- **Accessibility** — Enables keyboard and trackpad locking during **Screen Cleaning Mode**.

---

## How to Use R-Cleaner

### 1. First Launch & Intro Experience
- On first launch, R-Cleaner welcomes you with an animated `resitdc` brand intro and a time-of-day greeting from the built-in Voice AI.
- Click **Start Smart Care** to immediately run your first full Mac checkup, or **Explore Dashboard** to jump straight into the workspace.
- You can replay the intro animation anytime from the top macOS menu bar: **Care → Replay Intro** (or **Settings → General → Replay Intro Tour**).

### 2. Smart Care (All-in-One Checkup)
- Select **Smart Care** in the sidebar and click the central **Scan** orb.
- R-Cleaner runs a unified 5-pillar inspection across **Cleanup**, **Protection**, **Performance**, **Applications**, and **My Clutter**.
- Review any pillar in detail by clicking its tile, or click **Run** to clean junk, neutralize threats, run recommended maintenance tasks, and tidy duplicate downloads in one click.

### 3. Built-in Voice AI System (Zero Download Required)
- R-Cleaner ships with an embedded offline studio British male neural voice pack (`27` clips) and real-time `AVAudioEngine` HUD audio processing—no extra voice downloads needed.
- **Live Spoken System Briefing:** Click the **Voice AI** pill in the top-right corner of the window to hear an instant spoken briefing covering your live Mac health score, available storage, CPU/RAM load, and security status. Click again while speaking to stop.
- **Two-Way Jarvis Voice Commands (`⌘⇧J`):** Click the **Microphone** icon inside the top-right Voice AI pill (or press **`⌘⇧J`**) to open the holographic Jarvis Command Deck powered by offline on-device macOS Speech Recognition. Speak or type commands like *"Run Smart Care"*, *"Dev & AI Sweeper"*, *"Free up RAM"*, *"Flush DNS"*, *"Scan Space Lens on working directory"*, or *"What's eating my CPU?"*.
- **Quick Mute:** Click the speaker icon on the right side of the **Voice AI** pill to mute or unmute voice announcements anytime.
- **Customize:** Open **Settings → Voice AI** to toggle the bundled voice pack, toggle HUD audio processing & chimes, test the voice, or customize live TTS cadence and address title.

### 4. Individual Care Modules
| Module | What It Does & How to Use It |
| :--- | :--- |
| **Cleanup** | Click **Scan** to uncover **System Junk** (user/system caches, logs, Xcode DerivedData & Simulators, language files, universal binary slices, broken preferences, iOS backups), **Mail Attachments**, **Trash Bins** (local + mounted drives), and **AI Clutter** (Claude, Codex, Gemini, Cursor caches & Ollama/LM Studio/HuggingFace models). Review items per category and click **Clean**. |
| **Protection** | Choose **Quick**, **Balanced**, or **Deep** scan mode in Settings, then click **Scan** to inspect LaunchAgents/LaunchDaemons, Cronjobs, browser extensions, and Downloads for malware; clear **Safari / Chrome / Firefox** privacy traces; and review macOS **Application Permissions (TCC)**. |
| **Performance** | Run **8 Maintenance Tasks** (Free Up RAM, Flush DNS Cache, Free Purgeable Space, Thin Time Machine Snapshots, Reindex Spotlight, Run Periodic Scripts, Speed Up Mail, Repair Permissions) and toggle **Login Items** & **Background Items** (`launchctl`). |
| **Applications** | Completely uninstall apps along with their related Preferences, Caches, Logs, Containers, and Supporting Files (or **Reset** a misbehaving app without deleting it), check for **App Updates**, remove orphaned **Leftovers**, and clear unused `.dmg`/`.pkg` **Installers**. |
| **My Clutter** | Scan Home or any custom folder to detect **Exact Duplicates** (SHA-256 with Smart Selection), **Similar Images** (with blur detection & Best-to-Keep hints), **Large & Old Files**, and **Downloads** with source attribution. |
| **Space Lens** | Select any drive or folder to render an interactive **proportional bubble map** of your storage. Click bubbles to drill down, check **Purgeable Space**, and select large files/folders to remove directly. |
| **Dev & AI Sweeper** | Multi-core `getattrlistbulk` sweeper for developers & AI builders: discovers stale `node_modules`, Rust `target/`, Swift `.build/`, Gradle/Flutter `build/`, Python `.venv`, Pods, Xcode DerivedData & DeviceSupport, Android AVDs, global package caches (npm/pnpm/Cargo/Gradle/Go/Homebrew/uv), live Docker reclaimable caches, and local AI model weights (Ollama, LM Studio, HuggingFace) while auto-protecting active projects. |
| **Cloud Cleanup** | Automatically discovers **iCloud Drive**, **Google Drive**, **OneDrive**, and **Dropbox** synced folders so you can **Unsync (Evict Local Copy)** to free local SSD space without losing cloud files, or remove unneeded items. |
| **Email Cleanup** | Scans local Apple Mail `.emlx` archives to surface Smart Cleanup suggestions, Newsletters & Promotions, Subscriptions, Drafts, and Spam with an inline preview pane. |
| **My Tools** | Searchable quick-launch grid with pin-able **Favorites** to jump directly into specific tools (e.g., AI Clutter, Malware Finder, Free Up RAM, Screen Cleaning). |
| **Screen Cleaning Mode** | Click the display icon at the bottom-left of the sidebar (or from My Tools) to dim the screen into a smudge-revealing dark surface with keyboard lock. Press **`Esc`** when finished. |
| **Assistant & My Activity** | Click the top-right **Assistant %** pill to inspect your real-time **Mac Health Score (0–100)** and one-click recommendations, or open **My Activity** to view lifetime space freed and scan history. |

### 5. R-Cleaner Menu Bar Monitor
- Click the **R-Cleaner** icon in your macOS top menu bar anytime for an always-on live telemetry dashboard:
  - **Storage & Trash** quick free-space check & Empty Trash
  - **Memory** segmented usage bar, top memory consumers & one-click **Free Up RAM**
  - **CPU** live sparkline, uptime & top CPU processes
  - **Battery** cycle count, health & charging state
  - **Network** live Wi-Fi / throughput & built-in **Speed Test**
  - **External Drives** quick **Eject** / **Eject All**

---

## Local Build, Test & Packaging

Requires **macOS 14.0+** and **Xcode 15.3+ / Swift 5.10+**.

```bash
# Run all unit tests
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

---

## GitHub Actions CI/CD

- **CI (`.github/workflows/ci.yml`)**: Automatically runs `swift test`, builds a Universal (`arm64` + `x86_64`) `R-Cleaner.app`, packages `.dmg` and `.app.zip`, and uploads downloadable artifacts on every push or PR to `main`.
- **Release (`.github/workflows/release.yml`)**: Triggered automatically when pushing a version tag (e.g. `git tag v1.0.0 && git push origin v1.0.0`) or manually from the **Actions** tab. Publishes a GitHub Release with `R-Cleaner-<version>-universal.dmg`, `R-Cleaner-<version>-universal.app.zip`, and `SHA256SUMS.txt`.
  - Works out of the box with ad-hoc signing.
  - Optionally supports Apple Developer ID signing & notarization when these repository secrets are added: `MACOS_CERTIFICATE_P12` (base64 `.p12`), `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `APPLE_TEAM_ID`.
