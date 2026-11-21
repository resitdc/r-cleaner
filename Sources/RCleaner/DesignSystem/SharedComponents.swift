import SwiftUI
import AppKit

// MARK: - Glass Card Container

public struct GlassCard<Content: View>: View {
    public var padding: CGFloat
    public var cornerRadius: CGFloat
    public var highlightColor: Color?
    @ViewBuilder public let content: () -> Content

    @State private var isHovered = false

    public init(
        padding: CGFloat = 18,
        cornerRadius: CGFloat = 18,
        highlightColor: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.highlightColor = highlightColor
        self.content = content
    }

    public var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHovered ? RCleanerTheme.cardBackgroundHover : RCleanerTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        highlightColor?.opacity(0.55) ?? (isHovered ? RCleanerTheme.cardBorderHover : Color.white.opacity(0.22)),
                                        Color.white.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(isHovered ? 0.22 : 0.12), radius: isHovered ? 14 : 8, y: 4)
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }
}

// MARK: - Module Intro Screen Template

public struct ModuleIntroHero: View {
    public let title: String
    public let subtitle: String
    public let iconName: String
    public let palette: ModulePalette
    public let features: [(icon: String, title: String, detail: String)]
    public let primaryActionTitle: String
    public let secondaryActionTitle: String?
    public let onPrimaryAction: () -> Void
    public let onSecondaryAction: (() -> Void)?

    public init(
        title: String,
        subtitle: String,
        iconName: String,
        palette: ModulePalette,
        features: [(icon: String, title: String, detail: String)],
        primaryActionTitle: String = "Scan",
        secondaryActionTitle: String? = nil,
        onPrimaryAction: @escaping () -> Void,
        onSecondaryAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.palette = palette
        self.features = features
        self.primaryActionTitle = primaryActionTitle
        self.secondaryActionTitle = secondaryActionTitle
        self.onPrimaryAction = onPrimaryAction
        self.onSecondaryAction = onSecondaryAction
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            HStack(alignment: .center, spacing: 44) {
                // Left column: Title, subtitle, feature bullets
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text(subtitle)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(3)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(features.enumerated()), id: \.offset) { _, feat in
                            HStack(alignment: .top, spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(palette.primary.opacity(0.22))
                                        .frame(width: 34, height: 34)
                                    Image(systemName: feat.icon)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(palette.accent)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feat.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text(feat.detail)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.65))
                                        .lineLimit(2)
                                }
                            }
                        }
                    }

                    if let secondary = secondaryActionTitle, let onSecondary = onSecondaryAction {
                        Button(action: onSecondary) {
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3")
                                Text(secondary)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: 420, alignment: .leading)

                // Right column: Large glowing emblem illustration
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [palette.primary.opacity(0.42), palette.secondary.opacity(0.12), .clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: 150
                            )
                        )
                        .frame(width: 280, height: 280)

                    Circle()
                        .fill(.ultraThinMaterial.opacity(0.45))
                        .frame(width: 190, height: 190)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.45), palette.primary.opacity(0.35), .clear],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: palette.primary.opacity(0.35), radius: 24, y: 10)

                    Image(systemName: iconName)
                        .font(.system(size: 74, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, palette.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: palette.primary.opacity(0.6), radius: 14)
                }
            }
            .padding(.horizontal, 44)

            Spacer(minLength: 18)

            UbiquitousButton(
                title: primaryActionTitle,
                palette: palette,
                action: onPrimaryAction
            )
            .padding(.bottom, 22)
        }
    }
}

// MARK: - Animated Scanning Progress Screen

public struct ScanningProgressView: View {
    public let title: String
    public let subtitle: String
    public let currentPath: String
    public let progress: Double
    public let iconName: String
    public let palette: ModulePalette
    public let onStop: () -> Void

    @State private var rotation: Double = 0

    public init(
        title: String,
        subtitle: String,
        currentPath: String,
        progress: Double,
        iconName: String,
        palette: ModulePalette,
        onStop: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.currentPath = currentPath
        self.progress = progress
        self.iconName = iconName
        self.palette = palette
        self.onStop = onStop
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 6)
                    .frame(width: 168, height: 168)

                Circle()
                    .trim(from: 0, to: max(0.08, min(1.0, progress)))
                    .stroke(
                        AngularGradient(
                            colors: [palette.primary, palette.accent, palette.secondary, palette.primary],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 168, height: 168)
                    .rotationEffect(.degrees(rotation))
                    .animation(.easeOut(duration: 0.25), value: progress)

                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 132, height: 132)

                Image(systemName: iconName)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(colors: [.white, palette.accent], startPoint: .top, endPoint: .bottom)
                    )
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.74))

                if !currentPath.isEmpty {
                    Text(currentPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 520)
                        .padding(.top, 4)
                }
            }

            Spacer()

            UbiquitousButton(
                title: "Stop",
                palette: palette,
                isRunning: true,
                action: onStop
            )
            .padding(.bottom, 22)
        }
        .onAppear {
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Cleanup Completion View

public struct CleanupCompleteView: View {
    public let summary: CleanupSummary
    public let palette: ModulePalette
    public let onDone: () -> Void
    public let onReviewRemaining: (() -> Void)?

    @State private var showLog = false

    public init(
        summary: CleanupSummary,
        palette: ModulePalette,
        onDone: @escaping () -> Void,
        onReviewRemaining: (() -> Void)? = nil
    ) {
        self.summary = summary
        self.palette = palette
        self.onDone = onDone
        self.onReviewRemaining = onReviewRemaining
    }

    public var body: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "2ED573").opacity(0.35), .clear],
                            center: .center,
                            startRadius: 15,
                            endRadius: 95
                        )
                    )
                    .frame(width: 180, height: 180)

                Image(systemName: summary.itemsFailed > 0 && summary.itemsProcessed == 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 76))
                    .foregroundStyle(
                        summary.itemsFailed > 0 && summary.itemsProcessed == 0
                            ? Color.orange
                            : Color(hex: "2ED573")
                    )
            }

            VStack(spacing: 8) {
                Text(summary.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if summary.bytesFreed > 0 {
                    Text(ByteFormat.string(summary.bytesFreed))
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.white, palette.accent], startPoint: .leading, endPoint: .trailing)
                        )
                }

                Text("\(summary.itemsProcessed) items \(summary.subtitle)\(summary.itemsFailed > 0 ? " (\(summary.itemsFailed) failed)" : "")")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.75))
            }

            HStack(spacing: 12) {
                Button {
                    showLog = true
                } label: {
                    Label("View Log", systemImage: "doc.text.magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)

                if let onReviewRemaining {
                    Button(action: onReviewRemaining) {
                        Text("Review Remaining Items")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Color.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            UbiquitousButton(title: "Done", palette: palette, action: onDone)
                .padding(.bottom, 22)
        }
        .sheet(isPresented: $showLog) {
            CleanupLogSheet(entries: summary.logEntries, title: "Cleanup Log")
        }
    }
}

// MARK: - Cleanup Log Modal

public struct CleanupLogSheet: View {
    public let entries: [CleanupLogEntry]
    public let title: String
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Copy to Clipboard") {
                    let text = entries.map {
                        "[\($0.status.rawValue)] \($0.itemName) (\($0.path)) - \(ByteFormat.string($0.sizeBytes)) \($0.errorMessage ?? "")"
                    }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            if entries.isEmpty {
                ContentUnavailableView("No Log Entries", systemImage: "doc.text", description: Text("No items were processed in this operation."))
            } else {
                List(entries) { entry in
                    HStack {
                        Image(systemName: entry.status == .cleaned ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(entry.status == .cleaned ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.itemName).fontWeight(.medium)
                            Text(entry.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let err = entry.errorMessage {
                                Text(err)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Text(ByteFormat.string(entry.sizeBytes))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(width: 640, height: 440)
    }
}

// MARK: - Top Navigation Header Bar for Results / Data Manager

public struct ModuleHeaderBar: View {
    public let title: String
    public let backTitle: String
    public let onBack: () -> Void
    public var trailingText: String?

    public init(title: String, backTitle: String = "Start Over", trailingText: String? = nil, onBack: @escaping () -> Void) {
        self.title = title
        self.backTitle = backTitle
        self.trailingText = trailingText
        self.onBack = onBack
    }

    public var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text(backTitle)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let trailingText, !trailingText.isEmpty {
                    Text(trailingText)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.76))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 260) // Keeps header clear of top-right Voice AI + Assistant pills
        }
        .padding(.leading, 24)
        .padding(.trailing, 18)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

// MARK: - Byte Formatter Utility

public enum ByteFormat {
    private static let lock = NSLock()
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return f
    }()

    public static func string(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 KB" }
        if bytes < 1024 { return "< 1 KB" }
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(fromByteCount: bytes)
    }

    public static func speed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1024 {
            return String(format: "%.0f B/s", bytesPerSecond)
        } else if bytesPerSecond < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1024)
        } else {
            return String(format: "%.2f MB/s", bytesPerSecond / (1024 * 1024))
        }
    }

    public static func uptime(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let mins = totalMinutes % 60
        if days > 0 { return "\(days)d \(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    public static func itemCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return "\(count / 1_000_000)M items"
        } else if count >= 10_000 {
            return "\(count / 1_000)K items"
        } else if count >= 1_000 {
            let k = Double(count) / 1_000.0
            return String(format: "%.1fK items", k).replacingOccurrences(of: ".0K", with: "K")
        } else if count == 1 {
            return "1 item"
        } else {
            return "\(count) items"
        }
    }
}
