import Foundation
import Supabase
import SwiftUI
import UIKit

struct SettingsScreen: View {
    @Environment(\.sizeCategory) private var contentSizeCategory
    @Environment(AppStore.self) private var appStore
    @Environment(AppSettingsStore.self) private var appSettingsStore
    @Environment(AuthStore.self) private var authStore
    @Environment(GridPositionStore.self) private var gridPositionStore
    @Environment(OnboardingStore.self) private var onboardingStore
    @Environment(StreakStore.self) private var streakStore
    @Environment(TimeWindowStore.self) private var timeWindowStore
    @EnvironmentObject private var vpnManager: VPNManager

    @State private var destination: SettingsDestination?
    @State private var versionTapCount = 0
    @State private var isShowingShareSheet = false

    let onHome: () -> Void
    let onWindows: () -> Void
    let onAccountDeleted: () -> Void
    var showsDock: Bool

    init(
        onHome: @escaping () -> Void = {},
        onWindows: @escaping () -> Void = {},
        onAccountDeleted: @escaping () -> Void = {},
        showsDock: Bool = true
    ) {
        self.onHome = onHome
        self.onWindows = onWindows
        self.onAccountDeleted = onAccountDeleted
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
                title: "Account Settings",
                layout: layout,
                onBack: { destination = nil }
            ) {
                AccountSettingsPage(
                    onSignOut: logOutAndReturnHome,
                    onAccountDeleted: handleAccountDeleted
                )
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
                    SettingsNavigationRow(icon: "person", title: "Account Settings") {
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
                onboardingStore.resetForOnboardingRestart()
                appStore.resetAllBlockingOptions(source: "settings.logout_test_reset")
                onHome()
            }
        }
    }

    private func handleAccountDeleted() {
        appSettingsStore.resetForAccountDeletion()
        streakStore.resetForAccountDeletion()
        timeWindowStore.resetForAccountDeletion()
        gridPositionStore.resetForAccountDeletion()
        appStore.resetAllBlockingOptions(source: "settings.account_deletion")
        onboardingStore.resetForOnboardingRestart()
        onAccountDeleted()
    }
}

private enum SettingsDestination: Equatable {
    case account
    case notifications
    case windows
    case subscription
    case advanced
    case help
    case privacy
    case terms
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
    @Environment(AuthStore.self) private var authStore
    @Environment(AppSettingsStore.self) private var appSettingsStore
    @State private var draftName = ""
    @State private var isShowingDeleteAccountSheet = false

    let onSignOut: () -> Void
    let onAccountDeleted: () -> Void

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

                if !authStore.userEmail.isEmpty {
                    SettingsInlineDivider()

                    SettingsInfoRow(
                        title: "Email",
                        value: authStore.userEmail
                    )
                }

                SettingsInlineDivider()

                Button(action: onSignOut) {
                    SettingsActionRow(
                        title: "Sign out",
                        subtitle: nil,
                        icon: "rectangle.portrait.and.arrow.right"
                    )
                }
                .buttonStyle(.plain)
            }

            SettingsFormPanel {
                Button(role: .destructive) {
                    isShowingDeleteAccountSheet = true
                } label: {
                    SettingsActionRow(
                        title: "Delete Account",
                        subtitle: "Permanently delete your Nima account.",
                        icon: "trash",
                        foregroundStyle: .red
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            draftName = appSettingsStore.displayName
        }
        .sheet(isPresented: $isShowingDeleteAccountSheet) {
            DeleteAccountSheet(
                onDeleted: {
                    isShowingDeleteAccountSheet = false
                    onAccountDeleted()
                }
            )
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

private struct SubscriptionSettingsPage: View {
    @Environment(SubscriptionStore.self) private var subscriptionStore

    @State private var isShowingCancellationFeedback = false
    @State private var selectedCancellationReason: SubscriptionCancellationReason = .tooExpensive
    @State private var cancellationDetails = ""
    @State private var isSubmittingCancellationFeedback = false
    @State private var cancellationFeedbackError: String?
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
                    value: subscriptionStore.hasPremium ? "Active" : "No active subscription"
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

                Button(role: .destructive) {
                    cancellationFeedbackError = nil
                    isShowingCancellationFeedback = true
                } label: {
                    SettingsActionRow(
                        title: "Cancel subscription",
                        subtitle: nil,
                        icon: "xmark.circle"
                    )
                }
                .buttonStyle(.plain)

                if let subscriptionManagementError {
                    SettingsInlineDivider()

                    Text(subscriptionManagementError)
                        .font(.system(size: 13.5, weight: .regular, design: .rounded))
                        .foregroundStyle(.red.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 10)
                }
            }
        }
        .sheet(isPresented: $isShowingCancellationFeedback) {
            CancellationFeedbackSheet(
                selectedReason: $selectedCancellationReason,
                details: $cancellationDetails,
                isSubmitting: isSubmittingCancellationFeedback,
                errorMessage: cancellationFeedbackError,
                onSubmit: submitCancellationFeedback,
                onDismiss: {
                    isShowingCancellationFeedback = false
                }
            )
        }
    }

    private func submitCancellationFeedback() {
        guard !isSubmittingCancellationFeedback else { return }
        isSubmittingCancellationFeedback = true
        cancellationFeedbackError = nil

        Task {
            do {
                try await SubscriptionCancellationFeedbackService.submit(
                    reason: selectedCancellationReason,
                    details: cancellationDetails
                )
                await MainActor.run {
                    isSubmittingCancellationFeedback = false
                    isShowingCancellationFeedback = false
                    cancellationDetails = ""
                    openSubscriptionManagement()
                }
            } catch {
                await MainActor.run {
                    isSubmittingCancellationFeedback = false
                    cancellationFeedbackError = error.localizedDescription
                }
            }
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

private struct CancellationFeedbackSheet: View {
    @Binding var selectedReason: SubscriptionCancellationReason
    @Binding var details: String

    let isSubmitting: Bool
    let errorMessage: String?
    let onSubmit: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Tell us why before Apple opens subscription management.")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(AppChromePalette.muted.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)

                    SettingsFormPanel {
                        VStack(spacing: 0) {
                            ForEach(SubscriptionCancellationReason.allCases) { reason in
                                Button {
                                    selectedReason = reason
                                } label: {
                                    HStack {
                                        Text(reason.label)
                                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.white)

                                        Spacer()

                                        if selectedReason == reason {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(AppChromePalette.accent)
                                        }
                                    }
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if reason != SubscriptionCancellationReason.allCases.last {
                                    SettingsInlineDivider()
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Details optional")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)

                        TextEditor(text: detailsBinding)
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundStyle(.white)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 110)
                            .padding(8)
                            .background(AppChromePalette.card.opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(AppChromePalette.border.opacity(0.75), lineWidth: 1)
                            )

                        Text("\(details.count)/500")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(AppChromePalette.muted.opacity(0.78))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13.5, weight: .regular, design: .rounded))
                            .foregroundStyle(.red.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: onSubmit) {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.black)
                            }

                            Text(isSubmitting ? "Saving..." : "Continue to Apple")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.black)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppChromePalette.accent)
                        .clipShape(Capsule())
                    }
                    .disabled(isSubmitting)
                }
                .padding(20)
            }
            .background(AppChromePalette.background.ignoresSafeArea())
            .navigationTitle("Cancel subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", action: onDismiss)
                        .disabled(isSubmitting)
                }
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    private var detailsBinding: Binding<String> {
        Binding(
            get: { details },
            set: { details = String($0.prefix(500)) }
        )
    }
}

private struct DeleteAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var authStore

    @State private var isShowingFinalConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var subscriptionManagementError: String?

    let onDeleted: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Deleting your account permanently removes your Nima account and account-linked data.")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(AppChromePalette.muted.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)

                    SettingsFormPanel {
                        DeleteAccountBulletRow(
                            icon: "person.crop.circle.badge.xmark",
                            title: "Deletes your Nima account",
                            bodyText: "Your account and account-linked data will be removed."
                        )

                        SettingsInlineDivider()

                        DeleteAccountBulletRow(
                            icon: "creditcard",
                            title: "Does not cancel Apple billing",
                            bodyText: "Subscriptions managed by Apple must be cancelled separately."
                        )

                        SettingsInlineDivider()

                        DeleteAccountBulletRow(
                            icon: "exclamationmark.triangle",
                            title: "This is permanent",
                            bodyText: "You cannot undo account deletion after it completes."
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Deleting your account does not cancel subscriptions managed by Apple. To stop billing, cancel your subscription first in Manage Subscription.")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(AppChromePalette.muted.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            openSubscriptionManagement()
                        } label: {
                            HStack {
                                Text("Manage Subscription")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundStyle(AppChromePalette.accent)
                        }
                        .buttonStyle(.plain)

                        if let subscriptionManagementError {
                            Text(subscriptionManagementError)
                                .font(.system(size: 13.5, weight: .regular, design: .rounded))
                                .foregroundStyle(.red.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 4)

                    if let errorMessage {
                        Text("\(errorMessage) Contact support@nima.so if this keeps happening.")
                            .font(.system(size: 13.5, weight: .regular, design: .rounded))
                            .foregroundStyle(.red.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(role: .destructive) {
                        errorMessage = nil
                        isShowingFinalConfirmation = true
                    } label: {
                        HStack {
                            if isDeleting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            }

                            Text(isDeleting ? "Deleting..." : "Delete Account")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.red.opacity(isDeleting ? 0.48 : 0.82))
                        .clipShape(Capsule())
                    }
                    .disabled(isDeleting)
                }
                .padding(20)
            }
            .background(AppChromePalette.background.ignoresSafeArea())
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        guard !isDeleting else { return }
                        dismiss()
                    }
                    .disabled(isDeleting)
                }
            }
        }
        .interactiveDismissDisabled(isDeleting)
        .alert("Delete account permanently?", isPresented: $isShowingFinalConfirmation) {
            Button("Delete Account", role: .destructive) {
                deleteAccount()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete your Nima account and sign you out. Apple subscriptions must be cancelled separately.")
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    private func deleteAccount() {
        guard !isDeleting else { return }
        isDeleting = true
        errorMessage = nil

        Task {
            do {
                try await AccountDeletionService.deleteCurrentUser(isDemo: authStore.isDemo)
                await authStore.logout()
                await MainActor.run {
                    LocalAccountDataCleaner.clearAll()
                    isDeleting = false
                    onDeleted()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    errorMessage = error.localizedDescription
                }
            }
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

private struct DeleteAccountBulletRow: View {
    let icon: String
    let title: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(bodyText)
                    .font(.system(size: 13.5, weight: .regular, design: .rounded))
                    .foregroundStyle(AppChromePalette.muted.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
    }
}

enum AccountDeletionService {
    typealias RequestExecutor = (URLRequest) async throws -> (Data, URLResponse)
    typealias AccessTokenProvider = () async throws -> String

    static func deleteCurrentUser(
        isDemo: Bool,
        accountDeletionURL: URL? = configuredAccountDeletionURL,
        publishableKey: String? = configuredSupabasePublishableKey,
        accessTokenProvider: AccessTokenProvider = currentAccessToken,
        requestExecutor: @escaping RequestExecutor = { request in
            try await URLSession.shared.data(for: request)
        }
    ) async throws {
        guard !isDemo else { return }
        guard let accountDeletionURL else {
            throw AccountDeletionError.missingFunctionURL
        }

        let accessToken = try await accessTokenProvider()
        let request = try deletionRequest(
            accountDeletionURL: accountDeletionURL,
            accessToken: accessToken,
            publishableKey: publishableKey
        )
        let (data, response) = try await requestExecutor(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountDeletionError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AccountDeletionError.backend(
                statusCode: httpResponse.statusCode,
                message: backendErrorMessage(from: data)
            )
        }
    }

    static var configuredAccountDeletionURL: URL? {
        guard let supabaseURL = configuredSupabaseURL else {
            return nil
        }

        return supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("delete-account")
    }

    static func deletionRequest(
        accountDeletionURL: URL,
        accessToken: String,
        publishableKey: String? = configuredSupabasePublishableKey
    ) throws -> URLRequest {
        var request = URLRequest(url: accountDeletionURL)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let publishableKey {
            request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        }
        return request
    }

    private static var configuredSupabaseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return URL(string: trimmed)
    }

    private static var configuredSupabasePublishableKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_KEY") as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private static func currentAccessToken() async throws -> String {
        guard let supabaseClient else {
            throw AccountDeletionError.supabaseUnavailable
        }

        let session = try await supabaseClient.auth.session
        return session.accessToken
    }

    private static func backendErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? String,
           !error.isEmpty {
            return error
        }

        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

enum AccountDeletionError: LocalizedError, Equatable {
    case missingFunctionURL
    case supabaseUnavailable
    case invalidResponse
    case backend(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .missingFunctionURL:
            return "Account deletion is unavailable until Supabase is configured."
        case .supabaseUnavailable:
            return "Account deletion is unavailable until Supabase is configured."
        case .invalidResponse:
            return "Account deletion failed because the server returned an invalid response."
        case .backend(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Account deletion failed: \(message)"
            }
            return "Account deletion failed with status \(statusCode)."
        }
    }
}

private enum LocalAccountDataCleaner {
    static func clearAll() {
        if let defaults = UserDefaults(suiteName: NimaConstants.appGroupID) {
            defaults.removePersistentDomain(forName: NimaConstants.appGroupID)
            defaults.synchronize()
        }

        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: NimaConstants.appGroupID
        ) {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: containerURL,
                includingPropertiesForKeys: nil
            )) ?? []
            for url in contents {
                try? FileManager.default.removeItem(at: url)
            }
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
