import SwiftUI
import UIKit

struct TimeWindowsScreen: View {
    @EnvironmentObject private var store: TimeWindowStore
    @Environment(\.sizeCategory) private var contentSizeCategory
    @State private var editorPresentation: TimeWindowEditorPresentation?

    let onHome: () -> Void
    let onSettings: () -> Void
    var addWindowRequestID: UUID?
    var onAddWindowRequestHandled: (() -> Void)?
    var guidedWindowsEditorStep: GuidedWindowsEditorStep?
    var onGuidedWindowsEditorAdvance: () -> Void = {}
    var onGuidedWindowsEditorFinished: () -> Void = {}
    var showsDock = true

    @State private var handledAddWindowRequestID: UUID?

    var body: some View {
        GeometryReader { proxy in
            let layout = HomeDashboardLayout(
                screenSize: proxy.size,
                safeAreaInsets: proxy.safeAreaInsets,
                contentSizeCategory: contentSizeCategory
            )

            ZStack(alignment: .bottom) {
                TimeWindowsPalette.background
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    content(layout: layout)
                        .frame(width: layout.contentWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.top, layout.contentTopInset)
                        .padding(.bottom, layout.dockReservedHeight + 18 * layout.scale)
                }
                .nimaScrollBounceBasedOnSize()

                if showsDock {
                    AppBottomDock(
                        selected: .windows,
                        scale: layout.scale,
                        onHome: onHome,
                        onWindows: {},
                        onSettings: onSettings
                    )
                    .frame(width: layout.contentWidth, height: layout.dockHeight)
                    .padding(.bottom, layout.dockBottomPadding)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editorPresentation, onDismiss: {
            if guidedWindowsEditorStep != nil {
                onGuidedWindowsEditorFinished()
            }
        }) { presentation in
            TimeWindowEditorSheet(
                window: presentation.window,
                onSave: { window in
                    if presentation.window == nil {
                        store.addWindow(window)
                    } else {
                        store.updateWindow(window)
                    }
                },
                onDelete: { id in
                    store.deleteWindow(id: id)
                },
                guidedStep: guidedWindowsEditorStep,
                onGuidedStepAdvance: onGuidedWindowsEditorAdvance,
                onGuidedEditorFinished: onGuidedWindowsEditorFinished
            )
            .id(presentation.id)
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .onAppear {
            handleAddWindowRequestIfNeeded()
        }
        .onChange(of: addWindowRequestID) { _ in
            handleAddWindowRequestIfNeeded()
        }
    }

    private func handleAddWindowRequestIfNeeded() {
        guard let addWindowRequestID,
              handledAddWindowRequestID != addWindowRequestID else {
            return
        }
        handledAddWindowRequestID = addWindowRequestID
        editorPresentation = .add()
        onAddWindowRequestHandled?()
    }

    private func content(layout: HomeDashboardLayout) -> some View {
        let scale = layout.scale

        return VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: layout.topPadding)

            HomeLogo()
                .frame(width: layout.logoSize.width * 0.9, height: layout.logoSize.height * 0.9)
                .frame(maxWidth: .infinity)

            Color.clear.frame(height: 14 * scale)

            header(scale: scale)

            Color.clear.frame(height: 19 * scale)

            pauseAllRow(scale: scale)

            Color.clear.frame(height: 18 * scale)

            if store.windows.isEmpty {
                emptyState(scale: scale)
            } else {
                windowList(scale: scale)
            }

            Color.clear.frame(height: store.windows.isEmpty ? 17 * scale : 18 * scale)

            addButton(scale: scale)
                .frame(maxWidth: .infinity)

            Color.clear.frame(height: 18 * scale)
        }
    }

    private func header(scale: CGFloat) -> some View {
        let titleSize = min(36, max(27, 32.4 * scale))
        let subtitleSize = min(19.8, max(15.3, 18 * scale))

        return VStack(alignment: .leading, spacing: max(1, 2 * scale)) {
            Text("time windows")
                .font(.system(size: titleSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            Text("schedule periods for short form feeds\nto be blocked")
                .font(.system(size: subtitleSize, weight: .regular, design: .rounded))
                .foregroundStyle(TimeWindowsPalette.muted.opacity(0.92))
                .lineSpacing(-2)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pauseAllRow(scale: CGFloat) -> some View {
        let visualScale = min(1.06, max(0.9, scale))

        return HStack(alignment: .center, spacing: 14 * visualScale) {
            VStack(alignment: .leading, spacing: 3 * visualScale) {
                Text("pause all windows")
                    .font(.system(size: 22 * visualScale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text("temporarily disable all time windows")
                    .font(.system(size: 15.6 * visualScale, weight: .regular, design: .rounded))
                    .foregroundStyle(TimeWindowsPalette.muted.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { store.pauseAll },
                set: { store.setPauseAll($0) }
            ))
            .labelsHidden()
            .tint(TimeWindowsPalette.accent)
        }
    }

    private func emptyState(scale: CGFloat) -> some View {
        let visualScale = min(1.06, max(0.9, scale))

        return VStack(spacing: 10 * visualScale) {
            ZStack {
                RoundedRectangle(cornerRadius: 9 * visualScale, style: .continuous)
                    .fill(TimeWindowsPalette.accent.opacity(0.14))
                Image(systemName: "clock")
                    .font(.system(size: 31 * visualScale, weight: .medium))
                    .foregroundStyle(TimeWindowsPalette.accent)
            }
            .frame(width: 52 * visualScale, height: 52 * visualScale)

            VStack(spacing: 3 * visualScale) {
                Text("No time windows yet")
                    .font(.system(size: 19 * visualScale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("Create a schedule to block distractions automatically.")
                    .font(.system(size: 13.5 * visualScale, weight: .regular, design: .rounded))
                    .foregroundStyle(TimeWindowsPalette.muted.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36 * visualScale)
        .padding(.horizontal, 18 * visualScale)
        .background(
            RoundedRectangle(cornerRadius: 24 * visualScale, style: .continuous)
                .stroke(TimeWindowsPalette.border.opacity(0.78), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
        )
    }

    private func windowList(scale: CGFloat) -> some View {
        VStack(spacing: 12 * min(1.06, max(0.9, scale))) {
            ForEach(store.windows) { window in
                TimeWindowCard(
                    window: window,
                    status: store.status(for: window),
                    scale: scale,
                    onEdit: {
                        editorPresentation = .edit(window)
                    },
                    onToggle: { enabled in
                        store.setEnabled(enabled, for: window.id)
                    }
                )
            }
        }
    }

    private func addButton(scale: CGFloat) -> some View {
        let visualScale = min(1.06, max(0.9, scale))

        return Button {
            editorPresentation = .add()
        } label: {
            HStack(spacing: 7 * visualScale) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 19 * visualScale, weight: .bold))
                Text("add a time window")
                    .font(.system(size: 16.5 * visualScale, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13 * visualScale)
            .padding(.vertical, 7 * visualScale)
            .background(TimeWindowsPalette.accent.opacity(0.18))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct TimeWindowEditorPresentation: Identifiable {
    let id: String
    let window: TimeWindow?

    static func add() -> TimeWindowEditorPresentation {
        TimeWindowEditorPresentation(id: "add-\(UUID().uuidString)", window: nil)
    }

    static func edit(_ window: TimeWindow) -> TimeWindowEditorPresentation {
        TimeWindowEditorPresentation(id: "edit-\(window.id)", window: window)
    }
}

private struct TimeWindowCard: View {
    let window: TimeWindow
    let status: TimeWindowStatus
    let scale: CGFloat
    let onEdit: () -> Void
    let onToggle: (Bool) -> Void

    private var visualScale: CGFloat {
        min(1.06, max(0.9, scale))
    }

    var body: some View {
        HStack(spacing: 12 * visualScale) {
            Text(window.emoji)
                .font(.system(size: 29 * visualScale))
                .frame(width: 58 * visualScale, height: 58 * visualScale)
                .background(TimeWindowsPalette.tile)
                .clipShape(RoundedRectangle(cornerRadius: 16 * visualScale, style: .continuous))

            VStack(alignment: .leading, spacing: 3 * visualScale) {
                HStack(spacing: 6 * visualScale) {
                    Text(window.name)
                        .font(.system(size: 19.5 * visualScale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Text(TimeWindowScheduleEvaluator.repeatSummary(for: window.repeatDays))
                    .font(.system(size: 13.8 * visualScale, weight: .regular, design: .rounded))
                    .foregroundStyle(TimeWindowsPalette.muted)
                    .lineLimit(1)

                Text(TimeWindowScheduleEvaluator.timeRangeSummary(startTime: window.startTime, endTime: window.endTime))
                    .font(.system(size: 13.8 * visualScale, weight: .regular, design: .rounded))
                    .foregroundStyle(TimeWindowsPalette.muted)
                    .lineLimit(1)

                HStack(spacing: 4 * visualScale) {
                    ForEach(window.apps, id: \.self) { app in
                        SocialMediaIcon(platform: app, size: 15 * visualScale)
                    }
                    Text(appSummary(window.apps))
                        .font(.system(size: 12.5 * visualScale, weight: .medium, design: .rounded))
                        .foregroundStyle(TimeWindowsPalette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .padding(.top, 1 * visualScale)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 7 * visualScale) {
                Toggle("", isOn: Binding(
                    get: { window.enabled },
                    set: { onToggle($0) }
                ))
                .labelsHidden()
                .tint(TimeWindowsPalette.accent)

                Button(action: onEdit) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20 * visualScale, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30 * visualScale, height: 42 * visualScale)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(window.name)")
            }
        }
        .padding(.horizontal, 14 * visualScale)
        .padding(.vertical, 14 * visualScale)
        .background(
            RoundedRectangle(cornerRadius: 24 * visualScale, style: .continuous)
                .fill(TimeWindowsPalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24 * visualScale, style: .continuous)
                .strokeBorder(TimeWindowsPalette.border.opacity(0.82), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        status == .off ? window.name : "\(window.name), \(status.label)"
    }

    private func appSummary(_ apps: [String]) -> String {
        apps.map {
            switch $0 {
            case "instagram": return "Instagram"
            case "tiktok": return "TikTok"
            default: return $0.capitalized
            }
        }
        .joined(separator: ", ")
    }
}

enum TimeWindowEditorDefaults {
    static func repeatDays(for window: TimeWindow?) -> Set<TimeWindowWeekday> {
        guard let window else { return [] }
        return Set(window.repeatDays)
    }

    static func repeatSummaryText(for days: Set<TimeWindowWeekday>) -> String {
        days.isEmpty ? "Choose days" : TimeWindowScheduleEvaluator.repeatSummary(for: Array(days))
    }
}

private struct TimeWindowEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let window: TimeWindow?
    let onSave: (TimeWindow) -> Void
    let onDelete: (String) -> Void
    let guidedStep: GuidedWindowsEditorStep?
    let onGuidedStepAdvance: () -> Void
    let onGuidedEditorFinished: () -> Void

    @State private var emoji: String
    @State private var name: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var selectedApps: Set<String>
    @State private var selectedDays: Set<TimeWindowWeekday>
    @State private var validationMessage: String?
    @State private var isShowingEmojiPicker = false
    @State private var isShowingRepeat = false
    @State private var isShowingDeleteConfirmation = false

    init(
        window: TimeWindow?,
        onSave: @escaping (TimeWindow) -> Void,
        onDelete: @escaping (String) -> Void,
        guidedStep: GuidedWindowsEditorStep? = nil,
        onGuidedStepAdvance: @escaping () -> Void = {},
        onGuidedEditorFinished: @escaping () -> Void = {}
    ) {
        self.window = window
        self.onSave = onSave
        self.onDelete = onDelete
        self.guidedStep = guidedStep
        self.onGuidedStepAdvance = onGuidedStepAdvance
        self.onGuidedEditorFinished = onGuidedEditorFinished

        let draft = window ?? TimeWindow()
        _emoji = State(initialValue: draft.emoji)
        _name = State(initialValue: draft.name)
        _startDate = State(initialValue: Self.date(from: draft.startTime))
        _endDate = State(initialValue: Self.date(from: draft.endTime))
        _selectedApps = State(initialValue: Set(draft.apps))
        _selectedDays = State(initialValue: TimeWindowEditorDefaults.repeatDays(for: window))
    }

    var body: some View {
        ZStack {
            TimeWindowsPalette.background
                .ignoresSafeArea()

            VStack(spacing: 24) {
                sheetHeader

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 22) {
                        emojiPicker
                            .zIndex(guidedStep == .icon ? 100 : 0)
                        nameField
                        timePickers
                        appSelection
                        repeatRow

                        if let validationMessage {
                            Text(validationMessage)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if window != nil {
                            deleteButton
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 30)
                }
            }
            .padding(.top, 26)
        }
        .sheet(isPresented: $isShowingEmojiPicker) {
            EmojiPickerSheet(selectedEmoji: $emoji)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingRepeat) {
            RepeatSelectionSheet(selectedDays: $selectedDays)
                .presentationDetents([.fraction(0.68), .large])
        }
        .alert("Delete time window?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let id = window?.id {
                    onDelete(id)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This schedule will stop turning blockers on automatically.")
        }
        .onChange(of: isShowingRepeat) { isShowing in
            guard !isShowing else { return }
            advanceGuidedStepIfNeeded(.repeatDays)
        }
        .onChange(of: isShowingEmojiPicker) { isShowing in
            guard !isShowing else { return }
            advanceGuidedStepIfNeeded(.icon)
        }
        .onChange(of: name) { _ in
            advanceGuidedStepIfNeeded(.name)
        }
        .onChange(of: startDate) { _ in
            advanceGuidedStepIfNeeded(.time)
        }
        .onChange(of: endDate) { _ in
            advanceGuidedStepIfNeeded(.time)
        }
    }

    private var sheetHeader: some View {
        HStack {
            Button {
                finishGuidedEditorIfNeeded()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(TimeWindowsPalette.muted)
                    .frame(width: 46, height: 46)
                    .background(Circle().stroke(TimeWindowsPalette.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(window == nil ? "add window" : "edit window")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            Button {
                save()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(TimeWindowsPalette.background)
                    .frame(width: 46, height: 46)
                    .background(TimeWindowsPalette.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(window == nil ? "Save Window" : "Save Changes")
        }
        .padding(.horizontal, 28)
    }

    private var emojiPicker: some View {
        Button {
            isShowingEmojiPicker = true
        } label: {
            Text(emoji)
                .font(.system(size: 42))
                .frame(width: 82, height: 82)
                .background(TimeWindowsPalette.tile)
                .clipShape(Circle())
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(TimeWindowsPalette.accent)
                        .background(TimeWindowsPalette.background, in: Circle())
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Icon")
        .guidedWindowsCoachMark(
            isPresented: guidedStep == .icon,
            text: "Choose an icon so this window is\neasy to recognise",
            pointer: .up,
            offset: CGSize(width: 0, height: 55),
            onTap: onGuidedStepAdvance
        )
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .editorLabel()
            TextField("Work Focus", text: $name)
                .textInputAutocapitalization(.words)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(TimeWindowsPalette.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onTapGesture {
                    advanceGuidedStepIfNeeded(.name)
                }
        }
        .guidedWindowsCoachMark(
            isPresented: guidedStep == .name,
            content: guidedWindowsNameCoachText,
            pointer: .down,
            offset: CGSize(width: 0, height: -50),
            onTap: onGuidedStepAdvance
        )
    }

    private var timePickers: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Start")
                    .editorLabel()
                DatePicker("", selection: $startDate, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(TimeWindowsPalette.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text("End")
                    .editorLabel()
                DatePicker("", selection: $endDate, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(TimeWindowsPalette.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .guidedWindowsCoachMark(
            isPresented: guidedStep == .time,
            text: "Pick when your window should\nstart and end",
            pointer: .down,
            offset: CGSize(width: 0, height: -62),
            onTap: onGuidedStepAdvance
        )
    }

    private var appSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apps to block")
                .editorLabel()
            appRow(appID: "instagram", title: "Instagram")
            appRow(appID: "tiktok", title: "TikTok")
        }
        .guidedWindowsCoachMark(
            isPresented: guidedStep == .apps,
            text: "Select the feeds you want Nima to\nblock during this window",
            pointer: .up,
            offset: CGSize(width: 0, height: 61),
            onTap: onGuidedStepAdvance
        )
    }

    private func appRow(appID: String, title: String) -> some View {
        Button {
            toggleApp(appID)
            advanceGuidedStepIfNeeded(.apps)
        } label: {
            HStack(spacing: 12) {
                SocialMediaIcon(platform: appID, size: 28)
                Text(title)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: selectedApps.contains(appID) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(selectedApps.contains(appID) ? TimeWindowsPalette.accent : TimeWindowsPalette.muted)
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            .background(TimeWindowsPalette.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var repeatRow: some View {
        Button {
            isShowingRepeat = true
        } label: {
            HStack {
                Text("Repeat")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text(TimeWindowEditorDefaults.repeatSummaryText(for: selectedDays))
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(TimeWindowsPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.right")
                    .foregroundStyle(TimeWindowsPalette.muted)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(TimeWindowsPalette.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .guidedWindowsCoachMark(
            isPresented: guidedStep == .repeatDays,
            text: "Pick which days you want this\nwindow to run",
            pointer: .up,
            offset: CGSize(width: 0, height: 63),
            onTap: onGuidedStepAdvance
        )
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            isShowingDeleteConfirmation = true
        } label: {
            Text("Delete Window")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(TimeWindowsPalette.card)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func toggleApp(_ appID: String) {
        if selectedApps.contains(appID) {
            selectedApps.remove(appID)
        } else {
            selectedApps.insert(appID)
        }
    }

    private func save() {
        let startTime = Self.timeString(from: startDate)
        let endTime = Self.timeString(from: endDate)

        if TimeWindowScheduleEvaluator.minutes(from: startTime) == TimeWindowScheduleEvaluator.minutes(from: endTime) {
            validationMessage = "Start and end time can't be the same."
            return
        }
        if selectedApps.isEmpty {
            validationMessage = "Choose at least one app."
            return
        }
        if selectedDays.isEmpty {
            validationMessage = "Choose at least one day."
            return
        }

        let now = Date()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedWindow = TimeWindow(
            id: window?.id ?? "tw_\(UUID().uuidString)",
            name: trimmedName.isEmpty ? "Focus Time" : trimmedName,
            emoji: emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "⏰" : emoji,
            startTime: startTime,
            endTime: endTime,
            repeatDays: TimeWindowScheduleEvaluator.orderedUniqueDays(Array(selectedDays)),
            apps: selectedApps.sorted(),
            enabled: window?.enabled ?? true,
            createdAt: window?.createdAt ?? now,
            updatedAt: now
        )
        onSave(savedWindow)
        finishGuidedEditorIfNeeded()
        dismiss()
    }

    private func advanceGuidedStepIfNeeded(_ step: GuidedWindowsEditorStep) {
        guard guidedStep == step else { return }
        onGuidedStepAdvance()
    }

    private func finishGuidedEditorIfNeeded() {
        guard guidedStep != nil else { return }
        onGuidedEditorFinished()
    }

    private static func date(from time: String) -> Date {
        let minutes = TimeWindowScheduleEvaluator.minutes(from: time) ?? 9 * 60
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = minutes / 60
        components.minute = minutes % 60
        return Calendar.current.date(from: components) ?? Date()
    }

    private static func timeString(from date: Date) -> String {
        TimeWindowScheduleEvaluator.timeString(from: date)
    }
}

private enum GuidedWindowsCoachPointer {
    case up
    case down
}

private var guidedWindowsNameCoachText: some View {
    (
        Text("Choose a name, like\n")
            .font(.system(size: 18, weight: .semibold, design: .rounded))
        + Text("Morning Focus")
            .font(.system(size: 18, weight: .bold, design: .rounded))
        + Text(" or ")
            .font(.system(size: 18, weight: .semibold, design: .rounded))
        + Text("After Work")
            .font(.system(size: 18, weight: .bold, design: .rounded))
    )
}

private extension View {
    func guidedWindowsCoachMark(
        isPresented: Bool,
        text: String,
        pointer: GuidedWindowsCoachPointer,
        offset: CGSize,
        onTap: @escaping () -> Void
    ) -> some View {
        guidedWindowsCoachMark(
            isPresented: isPresented,
            content: Text(text)
                .font(.system(size: 18, weight: .bold, design: .rounded)),
            pointer: pointer,
            offset: offset,
            onTap: onTap
        )
    }

    func guidedWindowsCoachMark<CoachContent: View>(
        isPresented: Bool,
        content: CoachContent,
        pointer: GuidedWindowsCoachPointer,
        offset: CGSize,
        onTap: @escaping () -> Void
    ) -> some View {
        overlay(alignment: .top) {
            if isPresented {
                Button(action: onTap) {
                    GuidedWindowsCoachMark(pointer: pointer) {
                        content
                    }
                    .frame(width: min(UIScreen.main.bounds.width - 40, 360))
                }
                .buttonStyle(.plain)
                .offset(offset)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(20)
            }
        }
    }
}

private struct GuidedWindowsCoachMark<Content: View>: View {
    let pointer: GuidedWindowsCoachPointer
    let content: Content

    init(pointer: GuidedWindowsCoachPointer, @ViewBuilder content: () -> Content) {
        self.pointer = pointer
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if pointer == .up {
                GuidedWindowsCoachTriangle(pointsUp: true)
                    .fill(.white)
                    .frame(width: 24, height: 15)
            }

            content
                .foregroundStyle(Color(red: 0.01, green: 0.12, blue: 0.08))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white)
                )

            if pointer == .down {
                GuidedWindowsCoachTriangle(pointsUp: false)
                    .fill(.white)
                    .frame(width: 24, height: 15)
            }
        }
        .shadow(color: .black.opacity(0.32), radius: 10, y: 5)
    }
}

private struct GuidedWindowsCoachTriangle: Shape {
    let pointsUp: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointsUp {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}

private struct RepeatSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDays: Set<TimeWindowWeekday>

    var body: some View {
        NavigationStack {
            ZStack {
                TimeWindowsPalette.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ForEach(TimeWindowWeekday.allCases) { day in
                        repeatDayRow(day)

                        if day != TimeWindowWeekday.allCases.last {
                            Divider()
                                .overlay(TimeWindowsPalette.border)
                                .padding(.leading, 16)
                                .padding(.trailing, 12)
                        }
                    }
                }
                .background(TimeWindowsPalette.card)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle("Repeat")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(TimeWindowsPalette.accent)
                }
            }
        }
    }

    private func repeatDayRow(_ day: TimeWindowWeekday) -> some View {
        Button {
            toggle(day)
        } label: {
            HStack {
                Text(day.fullRepeatLabel)
                    .font(.system(size: 19, weight: .regular, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: selectedDays.contains(day) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selectedDays.contains(day) ? TimeWindowsPalette.accent : TimeWindowsPalette.muted)
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ day: TimeWindowWeekday) {
        if selectedDays.contains(day) {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }
}

private struct EmojiPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedEmoji: String
    @State private var searchText = ""
    @State private var selectedGroup: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 7)

    private var sections: [EmojiCatalogSection] {
        EmojiCatalog.filteredSections(
            query: searchText,
            selectedGroup: selectedGroup
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TimeWindowsPalette.background
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    searchField
                        .padding(.horizontal, 18)

                    categorySelector

                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            ForEach(sections) { section in
                                emojiSection(section)
                            }

                            if sections.isEmpty {
                                Text("No icons found")
                                    .font(.system(size: 18, weight: .medium, design: .rounded))
                                    .foregroundStyle(TimeWindowsPalette.muted)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 60)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 24)
                    }
                }
                .padding(.top, 12)
            }
            .navigationTitle("Choose Icon")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(TimeWindowsPalette.accent)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(TimeWindowsPalette.muted)

            TextField("Search icons", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundStyle(.white)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(TimeWindowsPalette.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(TimeWindowsPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var categorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryButton(title: "All", group: nil)
                ForEach(EmojiCatalog.groups, id: \.self) { group in
                    categoryButton(title: group, group: group)
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func categoryButton(title: String, group: String?) -> some View {
        let isSelected = selectedGroup == group

        return Button {
            selectedGroup = group
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? TimeWindowsPalette.background : .white)
                .lineLimit(1)
                .padding(.horizontal, 13)
                .frame(height: 34)
                .background(isSelected ? TimeWindowsPalette.accent : TimeWindowsPalette.card)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func emojiSection(_ section: EmojiCatalogSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.group)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(section.entries) { entry in
                    Button {
                        selectedEmoji = entry.emoji
                        dismiss()
                    } label: {
                        Text(entry.emoji)
                            .font(.system(size: 28))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .contentShape(Rectangle())
                            .overlay {
                                if entry.emoji == selectedEmoji {
                                    Circle()
                                        .stroke(TimeWindowsPalette.accent.opacity(0.72), lineWidth: 2)
                                        .frame(width: 38, height: 38)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.name)
                }
            }
        }
    }
}

private extension Text {
    func editorLabel() -> some View {
        self
            .font(.system(size: 19, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }
}

private enum TimeWindowsPalette {
    static let background = AppChromePalette.background
    static let card = Color(red: 0.035, green: 0.178, blue: 0.090)
    static let tile = Color(red: 0.855, green: 0.842, blue: 0.800)
    static let border = AppChromePalette.border
    static let accent = AppChromePalette.accent
    static let muted = AppChromePalette.muted
}

#Preview {
    TimeWindowsScreen(onHome: {}, onSettings: {})
        .environmentObject(TimeWindowStore())
        .preferredColorScheme(.dark)
}
