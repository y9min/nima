import SwiftUI
import UIKit

struct SettingsScreen: View {
    @Environment(\.sizeCategory) private var contentSizeCategory
    @Environment(AuthStore.self) private var authStore
    @EnvironmentObject private var vpnManager: VPNManager

    @State private var destination: SettingsDestination?
    @State private var versionTapCount = 0
    @State private var isShowingShareSheet = false

    let onHome: () -> Void
    let onWindows: () -> Void
    var showsDock: Bool

    init(
        onHome: @escaping () -> Void = {},
        onWindows: @escaping () -> Void = {},
        showsDock: Bool = true
    ) {
        self.onHome = onHome
        self.onWindows = onWindows
        self.showsDock = showsDock
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = HomeDashboardLayout(
                screenSize: proxy.size,
                safeAreaInsets: proxy.safeAreaInsets,
                contentSizeCategory: contentSizeCategory
            )

            ZStack(alignment: .bottom) {
                AppChromePalette.background
                    .ignoresSafeArea()

                page(layout: layout)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.16), value: destination)

                if showsDock {
                    AppBottomDock(
                        selected: .settings,
                        scale: layout.scale,
                        onHome: onHome,
                        onWindows: onWindows,
                        onSettings: { destination = nil }
                    )
                    .frame(width: layout.contentWidth, height: layout.dockHeight)
                    .padding(.bottom, layout.dockBottomPadding)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isShowingShareSheet) {
            ShareSheet(items: ["Try Nima to block distracting feeds."])
        }
    }

    @ViewBuilder
    private func page(layout: HomeDashboardLayout) -> some View {
        switch destination {
        case nil:
            settingsList(layout: layout)
        case .account?:
            SettingsPageScaffold(
                title: "Account Settings",
                layout: layout,
                onBack: { destination = nil }
            ) {
                AccountSettingsPage()
            }
        case .notifications?:
            SettingsPageScaffold(
                title: "Notifications",
                layout: layout,
                onBack: { destination = nil }
            ) {
                NotificationSettingsPage()
            }
        case .windows?:
            SettingsPageScaffold(
                title: "Windows",
                layout: layout,
                onBack: { destination = nil }
            ) {
                WindowsSettingsPage()
            }
        case .advanced?:
            SettingsPageScaffold(
                title: "Advanced",
                layout: layout,
                onBack: { destination = nil }
            ) {
                AdvancedSettingsPage()
            }
        case .help?:
            SettingsPageScaffold(
                title: "Help Centre",
                layout: layout,
                onBack: { destination = nil }
            ) {
                PlaceholderSettingsPage(
                    title: "Help Centre",
                    bodyText: "Support resources will live here."
                )
            }
        case .privacy?:
            SettingsPageScaffold(
                title: "Privacy Policy",
                layout: layout,
                onBack: { destination = nil }
            ) {
                PlaceholderSettingsPage(
                    title: "Privacy Policy",
                    bodyText: "Privacy details will live here."
                )
            }
        case .logs?:
            SettingsPageScaffold(
                title: "Logs",
                layout: layout,
                onBack: { destination = nil }
            ) {
                LogsSettingsPage()
            }
        }
    }

    private func settingsList(layout: HomeDashboardLayout) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsHeader(
                    title: "Settings",
                    scale: layout.scale,
                    onBack: onHome
                )

                Color.clear.frame(height: 22 * layout.settingsScale)

                VStack(spacing: 10 * layout.settingsScale) {
                    SettingsNavigationRow(icon: "person", title: "Account Settings") {
                        destination = .account
                    }
                    SettingsNavigationRow(icon: "bell", title: "Notifications") {
                        destination = .notifications
                    }
                    SettingsNavigationRow(icon: "clock", title: "Windows") {
                        destination = .windows
                    }
                    SettingsNavigationRow(icon: "wrench", title: "Advanced") {
                        destination = .advanced
                    }
                }

                SettingsDivider()
                    .padding(.top, 23 * layout.settingsScale)
                    .padding(.bottom, 19 * layout.settingsScale)

                VStack(alignment: .leading, spacing: 17 * layout.settingsScale) {
                    SettingsFooterButton(title: "Help Centre") {
                        destination = .help
                    }
                    SettingsFooterButton(title: "Privacy Policy") {
                        destination = .privacy
                    }
                    SettingsFooterButton(title: "Share This App") {
                        isShowingShareSheet = true
                    }
                    SettingsFooterButton(title: "Log Out") {
                        logOutAndReturnHome()
                    }
                }

                Text("Version \(appVersion)")
                    .font(.system(size: 16 * layout.settingsScale, weight: .regular, design: .rounded))
                    .foregroundStyle(AppChromePalette.muted)
                    .padding(.top, 23 * layout.settingsScale)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        versionTapCount += 1
                        if versionTapCount >= 3 {
                            versionTapCount = 0
                            vpnManager.refreshTunnelLog()
                            destination = .logs
                        }
                    }
            }
            .frame(width: layout.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.top, layout.settingsTopInset)
            .padding(.bottom, layout.dockReservedHeight + 22 * layout.settingsScale)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func logOutAndReturnHome() {
        Task {
            await authStore.logout()
            await MainActor.run {
                onHome()
            }
        }
    }
}

private enum SettingsDestination: Equatable {
    case account
    case notifications
    case windows
    case advanced
    case help
    case privacy
    case logs
}

private extension HomeDashboardLayout {
    var settingsScale: CGFloat {
        min(0.98, max(0.84, scale))
    }

    var settingsTopInset: CGFloat {
        max(0, contentTopInset + topPadding)
    }
}

private struct SettingsPageScaffold<Content: View>: View {
    let title: String
    let layout: HomeDashboardLayout
    let onBack: () -> Void
    let content: Content

    init(
        title: String,
        layout: HomeDashboardLayout,
        onBack: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.layout = layout
        self.onBack = onBack
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsHeader(
                    title: title,
                    scale: layout.scale,
                    onBack: onBack
                )

                Color.clear.frame(height: 29 * layout.settingsScale)

                content
            }
            .frame(width: layout.contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.top, layout.settingsTopInset)
            .padding(.bottom, layout.dockReservedHeight + 22 * layout.settingsScale)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct SettingsHeader: View {
    let title: String
    let scale: CGFloat
    let onBack: () -> Void

    private var visualScale: CGFloat {
        min(1.06, max(0.9, scale))
    }

    var body: some View {
        ZStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 23 * visualScale, weight: .medium))
                    .foregroundStyle(AppChromePalette.muted)
                    .frame(width: 43 * visualScale, height: 43 * visualScale)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.035))
                            .overlay(
                                Circle()
                                    .stroke(AppChromePalette.border.opacity(0.9), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(title)
                .font(.system(size: 29 * visualScale, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(height: 43 * visualScale)
    }
}

private struct SettingsNavigationRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 25, height: 28)

                Text(title)
                    .font(.system(size: 23, weight: .regular, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 23, weight: .regular))
                    .foregroundStyle(.white)
            }
            .frame(height: 31)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsFooterButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppChromePalette.border.opacity(0.9))
            .frame(height: 1)
    }
}

private struct SettingsFormPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppChromePalette.card.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppChromePalette.border.opacity(0.75), lineWidth: 1)
        )
    }
}

private struct SettingsToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13.5, weight: .regular, design: .rounded))
                        .foregroundStyle(AppChromePalette.muted.opacity(0.92))
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AppChromePalette.accent)
        }
        .padding(.vertical, 9)
    }
}

private struct SettingsInlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppChromePalette.border.opacity(0.62))
            .frame(height: 1)
    }
}

private struct AccountSettingsPage: View {
    @Environment(AppSettingsStore.self) private var appSettingsStore
    @State private var draftName = ""

    var body: some View {
        SettingsFormPanel {
            VStack(alignment: .leading, spacing: 9) {
                Text("Name")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                TextField("Name", text: $draftName)
                    .font(.system(size: 19, weight: .regular, design: .rounded))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AppChromePalette.border.opacity(0.8), lineWidth: 1)
                    )
                    .onChange(of: draftName) { _, newValue in
                        appSettingsStore.setDisplayName(newValue)
                    }
            }
            .padding(.vertical, 8)
        }
        .onAppear {
            draftName = appSettingsStore.displayName
        }
    }
}

private struct NotificationSettingsPage: View {
    @Environment(AppSettingsStore.self) private var appSettingsStore
    @Environment(StreakStore.self) private var streakStore
    @Environment(TimeWindowStore.self) private var timeWindowStore

    var body: some View {
        SettingsFormPanel {
            SettingsToggleRow(
                title: "Streak reminders",
                subtitle: "Daily reminder to keep your streak.",
                isOn: streakRemindersBinding
            )

            if appSettingsStore.streakRemindersEnabled {
                SettingsInlineDivider()

                HStack {
                    Text("Reminder time")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Spacer()

                    DatePicker("", selection: streakReminderDateBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(AppChromePalette.accent)
                }
                .padding(.vertical, 11)
            }

            SettingsInlineDivider()

            SettingsToggleRow(
                title: "Windows notifications",
                subtitle: "Window starts and pause reminders.",
                isOn: windowsNotificationsBinding
            )
        }
    }

    private var streakRemindersBinding: Binding<Bool> {
        Binding(
            get: { appSettingsStore.streakRemindersEnabled },
            set: {
                appSettingsStore.setStreakRemindersEnabled(
                    $0,
                    hasEarnedToday: streakStore.hasEarnedToday()
                )
            }
        )
    }

    private var windowsNotificationsBinding: Binding<Bool> {
        Binding(
            get: { appSettingsStore.windowsNotificationsEnabled },
            set: { enabled in
                appSettingsStore.setWindowsNotificationsEnabled(enabled)
                timeWindowStore.setWindowsNotificationsEnabled(enabled)
            }
        )
    }

    private var streakReminderDateBinding: Binding<Date> {
        Binding(
            get: {
                var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                components.hour = appSettingsStore.streakReminderHour
                components.minute = appSettingsStore.streakReminderMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                appSettingsStore.setStreakReminderTime(
                    hour: components.hour ?? AppSettingsStore.defaultStreakReminderHour,
                    minute: components.minute ?? AppSettingsStore.defaultStreakReminderMinute,
                    hasEarnedToday: streakStore.hasEarnedToday()
                )
            }
        )
    }
}

private struct WindowsSettingsPage: View {
    @Environment(AppSettingsStore.self) private var appSettingsStore
    @Environment(TimeWindowStore.self) private var timeWindowStore

    var body: some View {
        SettingsFormPanel {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pause toggle interval")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text("How long windows stay paused.")
                        .font(.system(size: 13.5, weight: .regular, design: .rounded))
                        .foregroundStyle(AppChromePalette.muted.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer()

                Picker("Pause toggle interval", selection: pauseIntervalBinding) {
                    ForEach(AppSettingsStore.allowedPauseIntervals, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(AppChromePalette.accent)
            }
            .padding(.vertical, 10)
        }
    }

    private var pauseIntervalBinding: Binding<Int> {
        Binding(
            get: { appSettingsStore.pauseIntervalMinutes },
            set: { minutes in
                appSettingsStore.setPauseIntervalMinutes(minutes)
                timeWindowStore.setPauseIntervalMinutes(minutes)
            }
        )
    }
}

private struct AdvancedSettingsPage: View {
    @Environment(AppSettingsStore.self) private var appSettingsStore
    @State private var isShowingResetConfirmation = false

    @AppStorage(BubbleConstants.udpSelectiveSafeModeEnabledKey,
                store: UserDefaults(suiteName: BubbleConstants.appGroupID))
    private var udpSelectiveSafeModeEnabled: Bool = true

    @AppStorage(BubbleConstants.udpDisabledFastRejectEnabledKey,
                store: UserDefaults(suiteName: BubbleConstants.appGroupID))
    private var udpDisabledFastRejectEnabled: Bool = false

    @AppStorage(BubbleConstants.tun2socksStartupModeKey,
                store: UserDefaults(suiteName: BubbleConstants.appGroupID))
    private var tun2socksStartupMode: String = BubbleConstants.tun2socksStartupModeStagedAfterConnect

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("These settings may affect performance and can block traffic that was not intended.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(AppChromePalette.muted.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

            SettingsFormPanel {
                SettingsToggleRow(
                    title: "Selective UDP Safe Mode",
                    subtitle: "Use safer targeted UDP handling.",
                    isOn: $udpSelectiveSafeModeEnabled
                )

                SettingsInlineDivider()

                SettingsToggleRow(
                    title: "Disable UDP Forwarding",
                    subtitle: "Fast reject UDP forwarding in the tunnel.",
                    isOn: $udpDisabledFastRejectEnabled
                )

                SettingsInlineDivider()

                SettingsToggleRow(
                    title: "Bypass SOCKS",
                    subtitle: "Applies on the next VPN start.",
                    isOn: tun2socksBypassBinding
                )
            }

            Button {
                isShowingResetConfirmation = true
            } label: {
                Text("Return to Default Settings")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(AppChromePalette.border.opacity(0.78), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .alert("Return to default settings?", isPresented: $isShowingResetConfirmation) {
            Button("Return to Default Settings", role: .destructive) {
                resetAdvancedDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only resets the advanced network settings.")
        }
    }

    private var tun2socksBypassBinding: Binding<Bool> {
        Binding(
            get: {
                tun2socksStartupMode == BubbleConstants.tun2socksStartupModeBypassDiagnostic
            },
            set: { enabled in
                tun2socksStartupMode = enabled
                    ? BubbleConstants.tun2socksStartupModeBypassDiagnostic
                    : BubbleConstants.tun2socksStartupModeStagedAfterConnect
            }
        )
    }

    private func resetAdvancedDefaults() {
        appSettingsStore.resetAdvancedDefaults()
        udpSelectiveSafeModeEnabled = true
        udpDisabledFastRejectEnabled = false
        tun2socksStartupMode = BubbleConstants.tun2socksStartupModeStagedAfterConnect
    }
}

private struct PlaceholderSettingsPage: View {
    let title: String
    let bodyText: String

    var body: some View {
        SettingsFormPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(bodyText)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(AppChromePalette.muted.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
    }
}

private enum LogSettingsSegment: String, CaseIterable, Identifiable {
    case app = "App Log"
    case diagnostic = "Diagnostic Report"

    var id: String { rawValue }
}

private struct LogsSettingsPage: View {
    @EnvironmentObject private var vpnManager: VPNManager
    @State private var selectedSegment: LogSettingsSegment = .app

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Logs", selection: $selectedSegment) {
                ForEach(LogSettingsSegment.allCases) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Button("Copy") {
                    UIPasteboard.general.string = visibleLogText
                }
                Button("Refresh") {
                    vpnManager.refreshTunnelLog()
                }
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(AppChromePalette.accent)

            ScrollView(.vertical, showsIndicators: true) {
                Text(visibleLogText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(minHeight: 300)
            .background(Color.black.opacity(0.32))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppChromePalette.border.opacity(0.72), lineWidth: 1)
            )
        }
        .onAppear {
            vpnManager.refreshTunnelLog()
        }
    }

    private var visibleLogText: String {
        switch selectedSegment {
        case .app:
            return vpnManager.statusLog.reversed().joined(separator: "\n")
        case .diagnostic:
            return vpnManager.tunnelLog
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Extension Log View (standalone route)

struct ExtensionLogView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vpnManager: VPNManager

    var body: some View {
        ZStack {
            AppChromePalette.background
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(vpnManager.tunnelLog.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                        Text(String(line))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: { BackArrowView() }
            }
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Button("Copy") {
                        UIPasteboard.general.string = vpnManager.tunnelLog
                    }
                    Button("Refresh") { vpnManager.refreshTunnelLog() }
                }
                .foregroundColor(.white)
            }
        }
        .onAppear {
            vpnManager.refreshTunnelLog()
        }
    }
}
