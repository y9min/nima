import Foundation
import SwiftUI
import UIKit

struct SettingsScreen: View {
    @Environment(\.sizeCategory) private var contentSizeCategory
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
            ShareSheet(items: ["Try Nima to block distracting feeds: \(NimaSupportURL.home.absoluteString)"])
        }
    }

    @ViewBuilder
    private func page(layout: HomeDashboardLayout) -> some View {
        switch destination {
        case nil:
            settingsList(layout: layout)
        case .account?:
            SettingsPageScaffold(
                title: "Profile",
                layout: layout,
                onBack: { destination = nil }
            ) {
                ProfileSettingsPage()
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
        case .subscription?:
            SettingsPageScaffold(
                title: "Subscription",
                layout: layout,
                onBack: { destination = nil }
            ) {
                SubscriptionSettingsPage()
            }
        case .advanced?:
            SettingsPageScaffold(
                title: "Advanced",
                layout: layout,
                onBack: { destination = nil }
            ) {
                AdvancedSettingsPage()
            }
        case .data?:
            SettingsPageScaffold(
                title: "Data",
                layout: layout,
                onBack: { destination = nil }
            ) {
                DataSettingsPage()
            }
        case .help?:
            SettingsPageScaffold(
                title: "Help Centre",
                layout: layout,
                onBack: { destination = nil }
            ) {
                ExternalLinkSettingsPage(
                    bodyText: "Setup, troubleshooting, billing and contact help are available on nima.so.",
                    buttonTitle: "Open Help Centre",
                    url: NimaSupportURL.help
                )
            }
        case .privacy?:
            SettingsPageScaffold(
                title: "Privacy Policy",
                layout: layout,
                onBack: { destination = nil }
            ) {
                ExternalLinkSettingsPage(
                    bodyText: "Read how nima handles privacy and data on nima.so.",
                    buttonTitle: "Open Privacy Policy",
                    url: NimaSupportURL.privacyPolicy
                )
            }
        case .terms?:
            SettingsPageScaffold(
                title: "Terms",
                layout: layout,
                onBack: { destination = nil }
            ) {
                ExternalLinkSettingsPage(
                    bodyText: "Read the terms that apply to using nima.",
                    buttonTitle: "Open Terms",
                    url: NimaSupportURL.terms
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
                    SettingsNavigationRow(icon: "person", title: "Profile") {
                        destination = .account
                    }
                    SettingsNavigationRow(icon: "bell", title: "Notifications") {
                        destination = .notifications
                    }
                    SettingsNavigationRow(icon: "clock", title: "Windows") {
                        destination = .windows
                    }
                    SettingsNavigationRow(icon: "creditcard", title: "Manage Subscription") {
                        destination = .subscription
                    }
                    SettingsNavigationRow(icon: "wrench", title: "Advanced") {
                        destination = .advanced
                    }
                    SettingsNavigationRow(icon: "externaldrive", title: "Data") {
                        destination = .data
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
                    SettingsFooterButton(title: "Terms & Conditions") {
                        destination = .terms
                    }
                    SettingsFooterButton(title: "Share This App") {
                        isShowingShareSheet = true
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

}

private enum SettingsDestination: Equatable {
    case account
    case notifications
    case windows
    case subscription
    case advanced
    case data
    case help
    case privacy
    case terms
    case logs
}

private struct DataSettingsPage: View {
    @Environment(InstagramProtectionStore.self) private var instagramProtectionStore
    @Environment(TikTokProtectionStore.self) private var tiktokProtectionStore
    @Environment(XProtectionStore.self) private var xProtectionStore
    @State private var confirmation: SocialDataControlRequest?
    @State private var workingProvider: SocialDataProvider?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Instagram, TikTok, and X website data is stored on this device by WebKit. Nima does not read your passwords, messages, or viewed content.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(AppChromePalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            dataSection(for: .instagram)
            dataSection(for: .tiktok)
            dataSection(for: .x)
        }
        .alert(item: $confirmation) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: .destructive(Text(action.buttonTitle)) {
                    perform(action)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func dataSection(for provider: SocialDataProvider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: provider.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppChromePalette.accent)
                    .frame(width: 22)

                Text(provider.title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }

            SettingsFormPanel {
                Button("Log Out of \(provider.title)") {
                    confirmation = SocialDataControlRequest(provider: provider, action: .logOut)
                }
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)

                SettingsInlineDivider()

                Button("Clear \(provider.title) Website Data", role: .destructive) {
                    confirmation = SocialDataControlRequest(provider: provider, action: .clearData)
                }
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
            }
            .disabled(workingProvider != nil)

            if workingProvider == provider {
                ProgressView("Updating \(provider.title) data…")
                    .tint(AppChromePalette.accent)
            }
        }
    }

    private func perform(_ request: SocialDataControlRequest) {
        let provider = request.provider
        workingProvider = provider
        Task {
            switch provider {
            case .instagram:
                switch request.action {
                case .logOut: await instagramProtectionStore.logOutInstagram()
                case .clearData: await instagramProtectionStore.clearInstagramData()
                }
            case .tiktok:
                switch request.action {
                case .logOut: await tiktokProtectionStore.logOutTikTok()
                case .clearData: await tiktokProtectionStore.clearTikTokData()
                }
            case .x:
                switch request.action {
                case .logOut: await xProtectionStore.logOutX()
                case .clearData: await xProtectionStore.clearXData()
                }
            }
            workingProvider = nil
        }
    }
}

private enum SocialDataProvider: String {
    case instagram
    case tiktok
    case x

    var title: String {
        switch self {
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .x: return "X"
        }
    }

    var icon: String {
        switch self {
        case .instagram: return "camera"
        case .tiktok: return "music.note"
        case .x: return "xmark"
        }
    }
}

private enum SocialDataAction: String {
    case logOut
    case clearData
}

private struct SocialDataControlRequest: Identifiable {
    let provider: SocialDataProvider
    let action: SocialDataAction

    var id: String { "\(provider.rawValue).\(action.rawValue)" }
    var title: String {
        action == .logOut
            ? "Log out of \(provider.title)?"
            : "Clear \(provider.title) data?"
    }
    var message: String {
        action == .logOut
            ? "You will need to sign in again inside Nima."
            : "This removes \(provider.title) sign-in details, cache, local storage, and other \(provider.title) website data from Nima."
    }
    var buttonTitle: String { action == .logOut ? "Log Out" : "Clear Data" }
}

private extension HomeDashboardLayout {
    var settingsScale: CGFloat {
        min(0.98, max(0.84, scale))
    }

    var settingsTopInset: CGFloat {
        max(0, contentTopInset + topPadding)
    }
}

private enum NimaSupportURL {
    static let home = URL(string: "https://nima.so/")!
    static let help = URL(string: "https://nima.so/help")!
    static let manage = URL(string: "https://nima.so/manage")!
    static let cancel = URL(string: "https://nima.so/cancel")!
    static let privacyPolicy = URL(string: "https://nima.so/privacy-policy")!
    static let terms = URL(string: "https://nima.so/terms-and-conditions")!
}

private enum AppleSubscriptionURL {
    static let manage = URL(string: "https://apps.apple.com/account/subscriptions")!
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
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 23, weight: .regular))
                    .foregroundStyle(.white)
            }
            .frame(minHeight: 44)
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
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13.5, weight: .regular, design: .rounded))
                        .foregroundStyle(AppChromePalette.muted.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
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

private struct ProfileSettingsPage: View {
    @Environment(AppSettingsStore.self) private var appSettingsStore
    @State private var draftName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                title: "Pause reminders",
                subtitle: "Reminds you when paused window blocking should return.",
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

private struct SubscriptionSettingsPage: View {
    @Environment(SubscriptionStore.self) private var subscriptionStore

    @State private var isShowingPlans = false
    @State private var subscriptionManagementError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Apple handles plan changes, renewals and cancellations. You can upgrade, downgrade or cancel from Apple subscriptions.")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(AppChromePalette.muted.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

            SettingsFormPanel {
                SettingsInfoRow(
                    title: "Status",
                    value: subscriptionStore.hasAccessForRouting ? "Active" : "No active subscription"
                )

                SettingsInlineDivider()

                Button {
                    openSubscriptionManagement()
                } label: {
                    SettingsActionRow(
                        title: "Manage plan",
                        subtitle: "Change, upgrade or cancel in the App Store.",
                        icon: "arrow.up.arrow.down"
                    )
                }
                .buttonStyle(.plain)

                SettingsInlineDivider()

                Button {
                    restorePurchases()
                } label: {
                    SettingsActionRow(
                        title: subscriptionStore.isRestoring ? "Restoring purchases…" : "Restore purchases",
                        subtitle: "Recover a subscription bought with your Apple Account.",
                        icon: "arrow.clockwise"
                    )
                }
                .buttonStyle(.plain)
                .disabled(subscriptionStore.isRestoring)

                if let restoreErrorMessage = subscriptionStore.restoreErrorMessage {
                    SettingsInlineDivider()

                    Text(restoreErrorMessage)
                        .font(.system(size: 13.5, weight: .regular, design: .rounded))
                        .foregroundStyle(.red.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 10)
                }

                if let subscriptionManagementError {
                    SettingsInlineDivider()

                    Text(subscriptionManagementError)
                        .font(.system(size: 13.5, weight: .regular, design: .rounded))
                        .foregroundStyle(.red.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 10)
                }
            }

            if !subscriptionStore.hasAccessForRouting {
                Button("View plans") {
                    isShowingPlans = true
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppChromePalette.accent)
                .frame(maxWidth: .infinity, alignment: .center)
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.subscription.view_plans")
            }
        }
        .fullScreenCover(isPresented: $isShowingPlans) {
            PaywallScreen(
                onUnlocked: {
                    isShowingPlans = false
                },
                context: "settings",
                onClose: {
                    isShowingPlans = false
                }
            )
        }
    }

    private func restorePurchases() {
        AnalyticsService.shared.capture(
            AnalyticsEvent.restoreStarted,
            properties: ["context": "settings"]
        )
        subscriptionStore.restore {
            AnalyticsService.shared.capture(
                AnalyticsEvent.restoreSucceeded,
                properties: ["context": "settings"]
            )
        }
    }

    private func openSubscriptionManagement() {
        subscriptionManagementError = nil

        UIApplication.shared.open(AppleSubscriptionURL.manage) { didOpen in
            guard !didOpen else { return }
            subscriptionManagementError = "Could not open Apple subscriptions right now."
        }
    }
}

private struct SettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(title)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Text(value)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(AppChromePalette.muted.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.vertical, 10)
    }
}

private struct SettingsActionRow: View {
    let title: String
    let subtitle: String?
    let icon: String
    var foregroundStyle: Color = .white

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(foregroundStyle)
                .frame(width: 24, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(foregroundStyle)
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

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppChromePalette.muted)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 10)
    }
}

private struct AdvancedSettingsPage: View {
    @Environment(AppSettingsStore.self) private var appSettingsStore
    @State private var isShowingResetConfirmation = false

    @AppStorage(NimaConstants.udpSelectiveSafeModeEnabledKey,
                store: UserDefaults(suiteName: NimaConstants.appGroupID))
    private var udpSelectiveSafeModeEnabled: Bool = true

    @AppStorage(NimaConstants.udpDisabledFastRejectEnabledKey,
                store: UserDefaults(suiteName: NimaConstants.appGroupID))
    private var udpDisabledFastRejectEnabled: Bool = false

    @AppStorage(NimaConstants.tun2socksStartupModeKey,
                store: UserDefaults(suiteName: NimaConstants.appGroupID))
    private var tun2socksStartupMode: String = NimaConstants.tun2socksStartupModeStagedAfterConnect

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
                tun2socksStartupMode == NimaConstants.tun2socksStartupModeBypassDiagnostic
            },
            set: { enabled in
                tun2socksStartupMode = enabled
                    ? NimaConstants.tun2socksStartupModeBypassDiagnostic
                    : NimaConstants.tun2socksStartupModeStagedAfterConnect
            }
        )
    }

    private func resetAdvancedDefaults() {
        appSettingsStore.resetAdvancedDefaults()
        udpSelectiveSafeModeEnabled = true
        udpDisabledFastRejectEnabled = false
        tun2socksStartupMode = NimaConstants.tun2socksStartupModeStagedAfterConnect
    }
}

private struct ExternalLinkSettingsPage: View {
    @Environment(\.openURL) private var openURL

    let bodyText: String
    let buttonTitle: String
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsFormPanel {
                Text(bodyText)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(AppChromePalette.muted.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }

            Button {
                openURL(url)
            } label: {
                HStack {
                    Text(buttonTitle)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(AppChromePalette.accent)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
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
