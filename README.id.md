<div align="center">

# R-Cleaner

**Aplikasi Native macOS untuk Pembersihan, Keamanan, Performa, dan Analisis Penyimpanan**  
*Dibangun menggunakan SwiftUI + AppKit oleh `resitdc` — lengkap dengan sistem Voice AI offline bergaya Jarvis*

<p>
  <a href="README.md">🇺🇸 English</a> &nbsp;|&nbsp; <strong>🇮🇩 Bahasa Indonesia</strong>
</p>

<p>
  <a href="https://github.com/resitdc/resitdc-mac-cleaner/releases/latest">
    <img src="https://img.shields.io/badge/Unduh_Versi_Terbaru-.dmg_%2F_.app-00B4D8?style=for-the-badge&logo=apple&logoColor=white" alt="Unduh Versi Terbaru" />
  </a>
</p>

<p>
  <a href="https://github.com/resitdc/resitdc-mac-cleaner/releases/latest">
    <img src="https://img.shields.io/github/v/release/resitdc/resitdc-mac-cleaner?style=flat-square&color=7B61FF&label=Versi%20Terbaru" alt="Versi Terbaru" />
  </a>
  <a href="https://github.com/resitdc/resitdc-mac-cleaner/actions/workflows/ci.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/resitdc/resitdc-mac-cleaner/ci.yml?branch=main&style=flat-square&label=CI%20Build" alt="Status CI" />
  </a>
  <img src="https://img.shields.io/badge/macOS-14.0%2B%20Universal%20(Apple%20Silicon%20%26%20Intel)-2ED573?style=flat-square&logo=apple" alt="macOS 14+ Universal" />
  <img src="https://img.shields.io/badge/Swift-5.10-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.10" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-38BDF8?style=flat-square" alt="MIT License" /></a>
</p>

</div>

---

## Unduh & Cara Instalasi

1. Klik tombol **Unduh Versi Terbaru** di atas atau buka halaman [GitHub Releases](https://github.com/resitdc/resitdc-mac-cleaner/releases/latest).
2. Unduh berkas **`R-Cleaner-<versi>-universal.dmg`** (mendukung native **Apple Silicon M1/M2/M3/M4** maupun **Intel** pada macOS 14.0 Sonoma atau lebih baru).
3. Klik ganda file `.dmg`, lalu seret (*drag*) **R-Cleaner** ke folder **Applications**.
4. Buka **R-Cleaner** dari folder **Applications** atau lewat Spotlight (`⌘ Space`).

> [!WARNING]
> **Peringatan Saat Membuka Pertama Kali (macOS Gatekeeper / "Apple could not verify R-Cleaner"):**  
> Karena R-Cleaner bersifat open-source dan menggunakan *ad-hoc signing* (tanpa sertifikat berbayar Apple Developer ID), macOS akan memblokir aplikasi saat pertama kali dibuka. Cara menyetujui dan membukanya dengan aman:
>
> **Cara 1 — Lewat System Settings (Disarankan di macOS 15 Sequoia ke atas):**
> 1. Coba buka **R-Cleaner** dari folder **Applications** sekali, lalu klik **Done** (atau **OK**) pada pop-up peringatan macOS.
> 2. Buka **System Settings** (Pengaturan Sistem) → **Privacy & Security** (Privasi & Keamanan).
> 3. **Scroll ke bawah** ke bagian **Security** — akan muncul pesan *"R-Cleaner was blocked to protect your Mac"*.
> 4. Klik **Open Anyway** (Tetap Buka), masukkan kata sandi Mac / Touch ID Anda, lalu konfirmasi **Open Anyway**.
>
> **Cara 2 — Satu Baris Perintah Terminal:**
> ```bash
> xattr -cr /Applications/R-Cleaner.app
> ```

### Izin macOS yang Disarankan (Opsional)
Agar pemindaian berjalan maksimal, Anda dapat mengaktifkan izin melalui **Settings → General → macOS System Permissions** di dalam R-Cleaner:
- **Full Disk Access** — Mengizinkan pemeriksaan cache Safari, lampiran Apple Mail, serta cache sistem/aplikasi yang terproteksi.
- **Accessibility** — Mengaktifkan penguncian keyboard & trackpad sementara saat menggunakan **Screen Cleaning Mode**.

---

## Cara Menggunakan R-Cleaner

### 1. Tampilan Awal & Animasi Intro
- Saat pertama kali dibuka, R-Cleaner menampilkan animasi pembuka berlogo `resitdc` disertai sapaan otomatis sesuai waktu (pagi/siang/malam) dari Voice AI bawaan.
- Klik **Start Smart Care** untuk langsung melakukan pemeriksaan menyeluruh pertama pada Mac Anda, atau pilih **Explore Dashboard** untuk langsung masuk ke tampilan utama.
- Anda dapat memutar ulang animasi intro kapan saja lewat menu bar atas macOS: **Care → Replay Intro** (atau **Settings → General → Replay Intro Tour**).

### 2. Smart Care (Pemeriksaan Menyeluruh 1-Klik)
- Pilih menu **Smart Care** di sidebar kiri lalu tekan tombol lingkaran **Scan** di bagian bawah.
- R-Cleaner otomatis memindai 5 pilar sekaligus: **Cleanup**, **Protection**, **Performance**, **Applications**, dan **My Clutter**.
- Klik salah satu kartu hasil untuk meninjau detail, atau klik **Run** untuk membersihkan file sampah, menghapus ancaman, menjalankan optimasi performa, dan merapikan file duplikat dalam sekali klik.

### 3. Sistem Voice AI Bawaan (Siap Pakai Tanpa Unduh Tambahan)
- R-Cleaner sudah dilengkapi paket suara neural British bergaya Jarvis secara offline (`27` klip terintegrasi di dalam aplikasi) lengkap dengan pemrosesan audio HUD real-time `AVAudioEngine`—pengguna **tidak perlu mengunduh suara tambahan**.
- **Briefing Sistem Langsung:** Klik tombol **Voice AI** di pojok kanan atas jendela untuk mendengarkan laporan suara real-time mengenai skor kesehatan Mac, kapasitas penyimpanan, beban CPU/RAM, dan status keamanan. Klik kembali untuk menghentikan suara.
- **Perintah Suara Dua Arah Jarvis (`⌘⇧J`):** Klik ikon **Mikrofon** di dalam tombol Voice AI (atau tekan **`⌘⇧J`**) untuk membuka Jarvis Command Deck berbasis pengenalan suara on-device macOS (100% offline & privat). Ucapkan atau ketik perintah seperti *"Run Smart Care"*, *"Dev & AI Sweeper"*, *"Free up RAM"*, *"Flush DNS"*, *"Scan Space Lens on working directory"*, atau *"What's eating my CPU?"*.
- **Mute Cepat:** Klik ikon speaker di sisi kanan tombol **Voice AI** untuk membisukan atau mengaktifkan kembali suara asisten kapan saja.
- **Kustomisasi:** Buka **Settings → Voice AI** untuk mengatur paket suara bawaan, efek audio HUD & chime, uji suara (*Test Built-in Jarvis Voice*), atau mengganti panggilan/kecepatan suara TTS.

### 4. Panduan Setiap Modul
| Modul | Fungsi & Cara Pemakaian |
| :--- | :--- |
| **Cleanup** | Klik **Scan** untuk menemukan **System Junk** (cache pengguna/sistem, log, Xcode DerivedData & Simulator, file bahasa tak terpakai, binary universal, preferensi rusak, backup iOS), **Mail Attachments**, **Trash Bins** (lokal + drive eksternal), dan **AI Clutter** (cache Claude, Codex, Gemini, Cursor serta model lokal Ollama/LM Studio/HuggingFace). Tinjau item per kategori lalu klik **Clean**. |
| **Protection** | Pilih mode **Quick**, **Balanced**, atau **Deep** di Settings, lalu klik **Scan** untuk memeriksa LaunchAgents/LaunchDaemons, Cronjobs, ekstensi browser, dan Downloads dari potensi malware; membersihkan jejak privasi **Safari / Chrome / Firefox**; serta mengaudit **Application Permissions (TCC)** macOS. |
| **Performance** | Jalankan **8 Tugas Maintenance** (Free Up RAM, Flush DNS Cache, Free Purgeable Space, Thin Time Machine Snapshots, Reindex Spotlight, Run Periodic Scripts, Speed Up Mail, Repair Permissions) serta kelola **Login Items** & **Background Items** (`launchctl`). |
| **Applications** | Hapus aplikasi secara tuntas beserta seluruh file terkaitnya (Preferences, Caches, Logs, Containers, Supporting Files), gunakan **Reset App** untuk mengembalikan aplikasi bermasalah ke setelan awal tanpa menghapusnya, periksa **App Updates**, bersihkan **Leftovers**, dan hapus file installer `.dmg`/`.pkg` lama. |
| **My Clutter** | Pindai folder Home atau folder pilihan Anda untuk menemukan **Duplicates** (deteksi SHA-256 akurat dengan Smart Selection), **Similar Images** (termasuk deteksi foto buram & rekomendasi *Best to Keep*), **Large & Old Files**, serta pengelola **Downloads**. |
| **Space Lens** | Pilih drive atau folder untuk menampilkan **peta gelembung (bubble map) interaktif** sesuai ukuran folder/file. Klik gelembung untuk masuk ke subfolder, pantau **Purgeable Space**, dan hapus file besar langsung dari tampilan visual. |
| **Dev & AI Sweeper** | Pembersih khusus developer & AI berbasis `getattrlistbulk` multi-core: mendeteksi `node_modules` lama, Rust `target/`, Swift `.build/`, Gradle/Flutter `build/`, Python `.venv`, Pods, Xcode DerivedData & DeviceSupport, Android AVD, cache package manager (npm/pnpm/Cargo/Gradle/Go/Homebrew/uv), cache Docker, serta model AI lokal (Ollama, LM Studio, HuggingFace) sambil melindungi proyek aktif secara otomatis. |
| **Port Killer** | Pusat kontrol TCP Port & Local Dev Server: mendeteksi port aktif (`:3000`, `:5173`, `:8080`, `:5432`, `:11434`), menampilkan folder proyek (`cwd`) dan framework (Vite, Next.js, Node, PostgreSQL, Redis, Ollama, ADB), menandai port yang terekspos ke jaringan LAN (`0.0.0.0` vs `localhost`), serta menyediakan tombol buka di browser, buka folder di Finder, dan Stop (`SIGTERM`) / Force Kill (`SIGKILL -9`) dalam 1 klik. |
| **Cloud Cleanup** | Mendeteksi otomatis folder lokal **iCloud Drive**, **Google Drive**, **OneDrive**, dan **Dropbox** sehingga Anda bisa melakukan **Unsync (Evict Local Copy)** untuk menghemat ruang SSD tanpa menghapus file di cloud, atau menghapus file yang tidak diperlukan. |
| **Email Cleanup** | Menganalisis arsip lokal Apple Mail (`.emlx`) untuk mengelompokkan saran Smart Cleanup, Newsletter & Promosi, Langganan, Draft, dan Spam lengkap dengan panel pratinjau email. |
| **My Tools** | Kumpulan pintasan cepat yang dapat dicari serta fitur **Favorites** untuk melompat langsung ke alat tertentu (AI Clutter, Malware Finder, Free Up RAM, Screen Cleaning, dll.). |
| **Screen Cleaning Mode** | Klik ikon layar di pojok kiri bawah sidebar (atau dari My Tools) untuk menggelapkan seluruh layar agar debu/noda terlihat jelas sekaligus mengunci keyboard sementara. Tekan tombol **`Esc`** jika sudah selesai mengelap layar. |
| **Assistant & My Activity** | Klik tombol **Assistant %** di pojok kanan atas untuk melihat **Skor Kesehatan Mac (0–100)** dan rekomendasi cepat, atau buka **My Activity** untuk melihat total ruang yang telah dihemat dan riwayat pemindaian. |

### 5. Monitor Menu Bar R-Cleaner
- Klik ikon **R-Cleaner** di menu bar atas macOS kapan saja untuk memantau kondisi Mac secara langsung:
  - **Storage & Trash:** pantau sisa ruang SSD & kosongkan Trash secara cepat
  - **Memory:** bar pemakaian RAM tersegmentasi, daftar aplikasi pemakan RAM terbesar, & tombol **Free Up RAM**
  - **CPU:** grafik beban CPU real-time, uptime sistem, & proses terberat
  - **Battery:** jumlah siklus (*cycle count*), kesehatan baterai, & status pengisian
  - **Network:** informasi Wi-Fi & kecepatan jaringan + **Speed Test** bawaan
  - **External Drives:** keluarkan drive eksternal dengan cepat (**Eject** / **Eject All**)

---

## Build Lokal dari Source Code

Membutuhkan **macOS 14.0+** dan **Xcode 15.3+ / Swift 5.10+**.

```bash
# Jalankan seluruh unit test
swift test

# Build & paketkan R-Cleaner.app native
chmod +x scripts/build_app.sh scripts/build_dmg.sh
./scripts/build_app.sh release

# Build Universal (Apple Silicon + Intel) .app, .dmg, dan .app.zip beserta SHA-256
UNIVERSAL=1 APP_VERSION=1.0.0 ./scripts/build_app.sh release
UNIVERSAL=1 APP_VERSION=1.0.0 ./scripts/build_dmg.sh

# Jalankan R-Cleaner.app
open dist/R-Cleaner.app
```

---

## CI/CD GitHub Actions

- **CI (`.github/workflows/ci.yml`)**: Otomatis menjalankan `swift test`, membangun `R-Cleaner.app` Universal (`arm64` + `x86_64`), memaketkan `.dmg` dan `.app.zip`, serta mengunggah artefak unduhan pada setiap push atau PR ke branch `main`.
- **Release (`.github/workflows/release.yml`)**: Berjalan otomatis saat mendorong tag versi (contoh: `git tag v1.0.0 && git push origin v1.0.0`) atau secara manual dari tab **Actions**. Otomatis menerbitkan GitHub Release berisi `R-Cleaner-<versi>-universal.dmg`, `R-Cleaner-<versi>-universal.app.zip`, dan `SHA256SUMS.txt`.
  - Langsung berfungsi menggunakan *ad-hoc signing* tanpa konfigurasi tambahan.
  - Mendukung *code signing* & *notarization* Apple Developer ID secara opsional bila secrets berikut diisi di repositori: `MACOS_CERTIFICATE_P12` (base64 `.p12`), `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, dan `APPLE_TEAM_ID`.

---

## Lisensi

Proyek ini dilisensikan di bawah [Lisensi MIT](LICENSE) — © 2026 [resitdc](https://resitdc.id).
