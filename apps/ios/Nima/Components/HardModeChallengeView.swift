import Lottie
import SwiftUI

struct HardModeActivationWarningCard: View {
    let onContinue: () -> Void
    let onNotYet: () -> Void

    var body: some View {
        DarkInstructionModalSurface {
            GeometryReader { proxy in
                let scale = min(1, max(0.72, min(proxy.size.width / 390, proxy.size.height / 700)))

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        Text("Hard Mode")
                            .font(.system(size: 38 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.top, 40 * scale)

                        Image("HardModeWarning")
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 184 * scale, height: 184 * scale)
                            .accessibilityHidden(true)
                            .padding(.top, 34 * scale)

                        Text("Hard Mode makes disabling app blocking a deliberate 5–10 minute process. All other Nima features, including Pause Mode, remain unaffected")
                            .font(.system(size: 21 * scale, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3 * scale)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 40)
                            .padding(.top, 30 * scale)

                        Spacer(minLength: 30 * scale)

                        Button(action: onContinue) {
                            Text("Continue")
                                .font(.system(size: 20 * scale, weight: .semibold, design: .rounded))
                                .foregroundStyle(.black)
                                .frame(width: 238 * scale, height: max(44, 50 * scale))
                                .background(AppChromePalette.accent)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("hard_mode.activation_warning.continue")

                        Button("Not yet", action: onNotYet)
                            .font(.system(size: 16 * scale, weight: .medium, design: .rounded))
                            .foregroundStyle(AppChromePalette.accent)
                            .buttonStyle(.plain)
                            .padding(.top, 18 * scale)
                            .padding(.bottom, 36 * scale)
                            .accessibilityIdentifier("hard_mode.activation_warning.not_yet")
                    }
                    .frame(width: proxy.size.width)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .accessibilityIdentifier("hard_mode.activation_warning")
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

struct HardModeChallengeOverlay: View {
    @Bindable var coordinator: HardModeCoordinator
    let onCommit: (HardModeCommit) -> HardModeCommitResult

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var traceStrokes: [[CGPoint]] = []
    @State private var activeTraceStroke: [CGPoint] = []
    @State private var tracePhraseIndex = 0
    @State private var sortedSlots = Array<Int?>(repeating: nil, count: 15)
    @State private var shuffledItems = HardModeSortChallenge.shuffledIDs()
    @State private var selectedSortItem: Int?
    @State private var selectedSortSlot: Int?
    @State private var showsOrderValidationErrors = false
    @State private var drawingStrokes: [[CGPoint]] = []
    @State private var activeDrawingStroke: [CGPoint] = []
    @State private var commitError: String?
    @State private var timerTick = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}

            VStack(spacing: 0) {
                header
                progress

                ScrollView(.vertical, showsIndicators: false) {
                    Group {
                        if let attempt = coordinator.activeAttempt {
                            switch attempt.step {
                            case .trace:
                                traceStep
                            case .shade:
                                shadeStep
                            case .draw:
                                drawStep
                            case .wait:
                                waitStep
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 22)
                    .padding(.bottom, 26)
                }

                footer
            }
            .background(HardModePalette.background)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 34,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 34,
                    style: .continuous
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 34,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 34,
                    style: .continuous
                )
                .strokeBorder(HardModePalette.border, lineWidth: 1)
            )
            .padding(.top, 34)
            .ignoresSafeArea(edges: .bottom)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom))
        }
        .alert("Couldn't change protection", isPresented: Binding(
            get: { commitError != nil },
            set: { if !$0 { commitError = nil } }
        )) {
            Button("Try again", role: .cancel) { commitError = nil }
        } message: {
            Text(commitError ?? "Protection is still on.")
        }
        .onChange(of: coordinator.activeAttempt?.step) { _, step in
            if step != .trace {
                traceStrokes = []
                activeTraceStroke = []
            }
        }
        .task(id: coordinator.activeAttempt?.step) {
            guard coordinator.activeAttempt?.step == .wait else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                timerTick &+= 1
                if coordinator.stepFourSecondsRemaining == 0 {
                    break
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                coordinator.cancelChallenge()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(HardModePalette.muted)
                    .frame(width: 44, height: 44)
                    .background(Circle().stroke(HardModePalette.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close challenge and discard progress")

            Spacer()

            VStack(spacing: 2) {
                Text("hard mode")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(coordinator.activeAttempt?.step.title ?? "")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(HardModePalette.muted)
            }

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
    }

    private var progress: some View {
        HStack(spacing: 7) {
            ForEach(HardModeChallengeStep.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(
                        step.rawValue <= (coordinator.activeAttempt?.step.rawValue ?? 1)
                            ? HardModePalette.accent
                            : HardModePalette.border
                    )
                    .frame(height: 5)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Step \(coordinator.activeAttempt?.step.rawValue ?? 1) of 4"
        )
    }

    private var traceStep: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Text("Trace the phrase")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("carefully trace each phrase to continue")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(HardModePalette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

            }
            .frame(maxWidth: .infinity)

            ZStack {
                Text("\(tracePhraseIndex + 1) of \(HardModeChallengeGeometry.phraseTexts.count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(HardModePalette.background)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(HardModePalette.accent, in: Capsule())

                HStack {
                    Spacer()
                    Button("Reset") {
                        traceStrokes = []
                        activeTraceStroke = []
                        coordinator.clearStepHint()
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
                }
            }

            Canvas { context, size in
                if let image = traceReferenceImage {
                    context.draw(
                        Image(uiImage: image),
                        in: fittedTraceImageRect(imageSize: image.size, canvasSize: size)
                    )
                } else {
                    let phrase = HardModeChallengeGeometry.phraseTexts[tracePhraseIndex]
                    let text = Text(phrase)
                        .font(.system(size: min(27, size.width / 12), weight: .semibold, design: .serif).italic())
                        .foregroundStyle(.white.opacity(0.13))
                    context.draw(text, at: CGPoint(x: size.width / 2, y: size.height * 0.48))

                    for group in phraseTargetGroups() {
                        for point in HardModePathScorer.resample(points: group, spacing: 0.009) {
                            let rect = CGRect(
                                x: point.x * size.width - 1.25,
                                y: point.y * size.height - 1.25,
                                width: 2.5,
                                height: 2.5
                            )
                            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.68)))
                        }
                    }
                }

                for stroke in visibleStrokes(traceStrokes, active: activeTraceStroke) {
                    guard stroke.count > 1 else { continue }
                    var path = Path()
                    path.move(to: scaled(stroke[0], in: size))
                    for point in stroke.dropFirst() {
                        path.addLine(to: scaled(point, in: size))
                    }
                    context.stroke(
                        path,
                        with: .color(HardModePalette.accent),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .frame(height: traceCanvasHeight)
            .background(HardModePalette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(HardModePalette.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(drawingGesture(
                strokes: $traceStrokes,
                activeStroke: $activeTraceStroke
            ))
            .accessibilityLabel("Trace \(HardModeChallengeGeometry.phraseTexts[tracePhraseIndex])")
            .accessibilityHint("Draw with one finger across the dotted phrase")

            if let hint = coordinator.stepHint {
                hintLabel(hint)
            }
        }
    }

    private var shadeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            challengeIntro(
                "Sort by size",
                detail: "Place all 15 circles from smallest to largest.",
                centered: true
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("place in order")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(HardModePalette.muted)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 5), spacing: 7) {
                    ForEach(Array(sortedSlots.enumerated()), id: \.offset) { index, itemID in
                        sortSlot(index: index, itemID: itemID)
                            .dropDestination(for: String.self) { values, _ in
                                guard let value = values.first,
                                      let droppedID = Int(value) else { return false }
                                placeSortItem(droppedID, in: index)
                                return true
                            }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("available")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(HardModePalette.muted)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 5), spacing: 7) {
                    ForEach(availableSortItems, id: \.self) { itemID in
                        Button {
                            selectedSortItem = itemID
                            selectedSortSlot = nil
                            coordinator.clearStepHint()
                        } label: {
                            sortTile(itemID)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .strokeBorder(
                                            selectedSortItem == itemID ? Color.white : .clear,
                                            lineWidth: 2
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .draggable(String(itemID)) {
                            sortTile(itemID).frame(width: 48, height: 48)
                        }
                        .accessibilityLabel("Unplaced item \(displayRank(for: itemID))")
                    }
                }
            }

            if let hint = coordinator.stepHint {
                hintLabel(hint)
            }
        }
    }

    private var drawStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            challengeIntro(
                activeDrawTarget.drawTitle,
                detail: "Trace the dotted reference at a comfortable size. Cover the full outline."
            )

            HStack {
                Label("\(activeDrawTarget.objectName) reference", systemImage: activeDrawTarget.systemImageName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(HardModePalette.muted)
                Spacer()
                Button("Clear") {
                    drawingStrokes = []
                    activeDrawingStroke = []
                    coordinator.clearStepHint()
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .buttonStyle(.plain)
            }

            Canvas { context, size in
                drawGrid(context: &context, size: size)
                if let image = drawReferenceImage {
                    context.draw(
                        Image(uiImage: image),
                        in: fittedTraceImageRect(
                            imageSize: image.size,
                            canvasSize: size,
                            inset: drawReferenceInset
                        )
                    )
                } else {
                    drawDotted(
                        points: HardModeChallengeGeometry.palmTrunk,
                        context: &context,
                        size: size
                    )
                    drawDotted(
                        points: HardModeChallengeGeometry.palmFronds,
                        context: &context,
                        size: size
                    )
                    drawDotted(
                        points: HardModeChallengeGeometry.palmGround,
                        context: &context,
                        size: size
                    )
                }

                for stroke in visibleStrokes(drawingStrokes, active: activeDrawingStroke) {
                    guard stroke.count > 1 else { continue }
                    var path = Path()
                    path.move(to: scaled(stroke[0], in: size))
                    for point in stroke.dropFirst() {
                        path.addLine(to: scaled(point, in: size))
                    }
                    context.stroke(
                        path,
                        with: .color(HardModePalette.accent),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .frame(height: 330)
            .background(HardModePalette.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(HardModePalette.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(drawingGesture(
                strokes: $drawingStrokes,
                activeStroke: $activeDrawingStroke
            ))
            .accessibilityLabel(activeDrawTarget.drawTitle)
            .accessibilityHint("Trace the dotted outline with one finger")

            if let hint = coordinator.stepHint {
                hintLabel(hint)
            }
        }
    }

    private var waitStep: some View {
        VStack(spacing: 16) {
            challengeIntro(
                "Let the paint dry",
                detail: "Keep Nima open for the full 60 seconds. Leaving or backgrounding the app resets this step."
            )

            if timerIsComplete {
                finalChoices
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                    VStack(spacing: 10) {
                        LottieView(animation: .named(
                            "nima_paint_drying",
                            subdirectory: "PaintDrying"
                        ))
                            .imageProvider(BundleImageProvider(
                                bundle: .main,
                                searchPath: "PaintDrying"
                            ))
                            .currentProgress(coordinator.stepFourProgress)
                            .configure { view in
                                view.loopMode = .playOnce
                                view.backgroundBehavior = .pauseAndRestore
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: 350)
                            .frame(height: 330)
                            .accessibilityLabel("Paint drying progress")
                            .accessibilityValue("\(Int(coordinator.stepFourProgress * 100)) percent")

                        Text(timeString(seconds: coordinator.stepFourSecondsRemaining))
                            .font(.system(size: 34, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }
                }
            }
        }
    }

    private var finalChoices: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(coordinator.activeAttempt?.change.mutation == .turnOffHardMode
                ? "Turn off Hard Mode?"
                : "Choose what happens next")
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(affectedAppsDescription)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(HardModePalette.muted)

            if coordinator.activeAttempt?.change.mutation == .turnOffHardMode {
                choiceButton("Turn off Hard Mode", icon: "power") {
                    choose(.off)
                }
            } else {
                ForEach([5, 10, 15], id: \.self) { minutes in
                    choiceButton("Pause \(minutes) min", icon: "pause.fill") {
                        choose(.pause(minutes: minutes))
                    }
                }
                choiceButton("Turn off until I turn it back on", icon: "xmark.circle") {
                    choose(.off)
                }
            }

            if let error = coordinator.errorMessage {
                hintLabel(error, isError: true)
            }
        }
        .padding(.top, 8)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if coordinator.activeAttempt?.step != .wait
                || !timerIsComplete {
                Button(action: continueTapped) {
                    Text(coordinator.activeAttempt?.step == .wait
                        ? "\(coordinator.stepFourSecondsRemaining)s"
                        : "Continue")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            canContinue
                                ? HardModePalette.background
                                : HardModePalette.muted.opacity(0.65)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            canContinue || coordinator.activeAttempt?.step == .wait
                                ? HardModePalette.accent
                                : HardModePalette.card,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canContinue)
            }

            if let hint = coordinator.stepHint, coordinator.activeAttempt?.step == .wait {
                Text(hint)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(HardModePalette.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(HardModePalette.background.opacity(0.98))
    }

    private var canContinue: Bool {
        guard let step = coordinator.activeAttempt?.step else { return false }
        switch step {
        case .trace: return traceStrokes.contains(where: { $0.count >= 2 })
        case .shade: return sortedSlots.allSatisfy { $0 != nil }
        case .draw: return drawingStrokes.contains(where: { $0.count >= 2 })
        case .wait: return coordinator.stepFourSecondsRemaining == 0
        }
    }

    private var timerIsComplete: Bool {
        _ = timerTick
        return coordinator.isAwaitingFinalChoice
    }

    private func continueTapped() {
        guard let step = coordinator.activeAttempt?.step else { return }
        switch step {
        case .trace:
            let result: HardModeCoverageResult
            if let image = traceReferenceImage {
                result = HardModeRasterTraceScorer.evaluate(
                    image: image,
                    drawingGroups: traceStrokes,
                    canvasSize: traceSurfaceSize,
                    imageInset: traceReferenceInset,
                    tolerance: 0.07
                )
            } else {
                result = HardModePathScorer.evaluate(
                    targetGroups: phraseTargetGroups(),
                    drawingGroups: traceStrokes,
                    tolerance: 0.07,
                    minimumRegions: 3
                )
            }
            guard result.passed else {
                coordinator.showStepHint(
                    "Cover more of the phrase and keep the line close to the dots."
                )
                return
            }
            if tracePhraseIndex < HardModeChallengeGeometry.phraseTexts.count - 1 {
                tracePhraseIndex += 1
                traceStrokes = []
                activeTraceStroke = []
                coordinator.clearStepHint()
            } else {
                coordinator.advanceStep()
            }
        case .shade:
            guard HardModeSortChallenge.isCorrect(sortedSlots) else {
                showsOrderValidationErrors = true
                coordinator.showStepHint(
                    "Not quite — check the highlighted circles, then continue."
                )
                return
            }
            showsOrderValidationErrors = false
            coordinator.advanceStep()
        case .draw:
            let result: HardModeCoverageResult
            if let image = drawReferenceImage {
                result = HardModeRasterTraceScorer.evaluate(
                    image: image,
                    drawingGroups: drawingStrokes,
                    canvasSize: traceSurfaceSize,
                    imageInset: drawReferenceInset,
                    tolerance: 0.075,
                    minimumCoverage: 0.35,
                    minimumInkPrecision: 0.35,
                    minimumRegions: 2
                )
            } else {
                result = HardModePathScorer.evaluate(
                    targetGroups: [
                        HardModeChallengeGeometry.palmTrunk,
                        HardModeChallengeGeometry.palmFronds
                    ],
                    drawingGroups: drawingStrokes,
                    tolerance: 0.07,
                    minimumCoverage: 0.35,
                    minimumInkPrecision: 0.35,
                    minimumRegions: 2,
                    minimumCoveragePerRequiredGroup: 0.18
                )
            }
            guard result.passed else {
                coordinator.showStepHint(
                    "That was close. Trace more of the full outline and keep the line close to the dots."
                )
                return
            }
            coordinator.advanceStep()
        case .wait:
            guard coordinator.stepFourSecondsRemaining == 0 else {
                coordinator.showStepHint("The paint is still wet.")
                return
            }
        }
    }

    private func choose(_ choice: HardModeCommitChoice) {
        guard let commit = coordinator.authorizeFinalChoice(choice) else { return }
        let result = onCommit(commit)
        coordinator.finishCommit(commit, result: result)
        if case .failure(let message) = result {
            commitError = message
        } else if case .stale(let message) = result {
            commitError = message
        }
    }

    private func challengeIntro(
        _ title: String,
        detail: String,
        centered: Bool = false
    ) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(centered ? .center : .leading)
            Text(detail)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(HardModePalette.muted)
                .multilineTextAlignment(centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(
            maxWidth: .infinity,
            alignment: centered ? .center : .leading
        )
    }

    private func hintLabel(_ text: String, isError: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(isError ? HardModePalette.warning : HardModePalette.accent)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                (isError ? HardModePalette.warning : HardModePalette.accent)
                    .opacity(0.09),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }

    private func choiceButton(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(HardModePalette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(HardModePalette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var affectedAppsDescription: String {
        let appIDs = coordinator.activeAttempt?.change.affectedAppIDs ?? []
        guard !appIDs.isEmpty else {
            return "Your blockers keep their current settings."
        }
        let names = appIDs.sorted().map { appID in
            switch appID {
            case "instagram": "Instagram"
            case "tiktok": "TikTok"
            case "x": "X"
            default: appID.capitalized
            }
        }
        return "This applies to \(names.joined(separator: ", "))."
    }

    private func drawingGesture(
        strokes: Binding<[[CGPoint]]>,
        activeStroke: Binding<[CGPoint]>
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard value.startLocation.x >= 0, value.startLocation.y >= 0 else { return }
                let point = normalizedDrawingPoint(value.location)
                if let last = activeStroke.wrappedValue.last,
                   hypot(point.x - last.x, point.y - last.y) < 0.004 {
                    return
                }
                activeStroke.wrappedValue.append(point)
            }
            .onEnded { value in
                let point = normalizedDrawingPoint(value.location)
                if let last = activeStroke.wrappedValue.last,
                   hypot(point.x - last.x, point.y - last.y) >= 0.004 {
                    activeStroke.wrappedValue.append(point)
                }
                if activeStroke.wrappedValue.count >= 2 {
                    strokes.wrappedValue.append(activeStroke.wrappedValue)
                }
                activeStroke.wrappedValue = []
            }
    }

    private func normalizedDrawingPoint(_ location: CGPoint) -> CGPoint {
        CGPoint(
            x: min(1, max(0, location.x / max(traceSurfaceSize.width, 1))),
            y: min(1, max(0, location.y / max(traceSurfaceSize.height, 1)))
        )
    }

    private func visibleStrokes(_ strokes: [[CGPoint]], active: [CGPoint]) -> [[CGPoint]] {
        active.count >= 2 ? strokes + [active] : strokes
    }

    // The Canvas and gesture share the GeometryReader-provided surface size.
    // Keeping this stable avoids changing hit-test coordinates after rotation.
    private var traceSurfaceSize: CGSize {
        let sceneWidth = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width ?? 390
        let height: CGFloat
        if coordinator.activeAttempt?.step == .draw {
            height = 330
        } else if tracePhraseIndex == 0 {
            height = 280
        } else {
            height = 220
        }
        return CGSize(width: max(1, sceneWidth - 44), height: height)
    }

    private var traceCanvasHeight: CGFloat {
        tracePhraseIndex == 0 ? 280 : 220
    }

    private var traceReferenceInset: CGFloat {
        20
    }

    private var traceReferenceImage: UIImage? {
        UIImage(named: traceReferenceImageName)
    }

    private var activeDrawTarget: HardModeDrawTarget {
        coordinator.activeAttempt?.drawTarget ?? .palmTree
    }

    private var drawReferenceImage: UIImage? {
        UIImage(named: activeDrawTarget.referenceImageName)
    }

    private var drawReferenceInset: CGFloat {
        12
    }

    private var traceReferenceImageName: String {
        switch tracePhraseIndex {
        case 0:
            return "HardModeTraceScrollingEnemy"
        case 1:
            return "HardModeTraceDisciplineBeatsMotivation"
        default:
            return "HardModeTraceMyTimeIsWorthMore"
        }
    }

    private func fittedTraceImageRect(
        imageSize: CGSize,
        canvasSize: CGSize,
        inset: CGFloat? = nil
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: canvasSize)
        }
        let resolvedInset = min(
            inset ?? traceReferenceInset,
            min(canvasSize.width, canvasSize.height) / 2 - 1
        )
        let availableWidth = max(1, canvasSize.width - resolvedInset * 2)
        let availableHeight = max(1, canvasSize.height - resolvedInset * 2)
        let imageAspect = imageSize.width / imageSize.height
        let availableAspect = availableWidth / availableHeight
        if imageAspect > availableAspect {
            let fittedHeight = availableWidth / imageAspect
            return CGRect(
                x: resolvedInset,
                y: (canvasSize.height - fittedHeight) / 2,
                width: availableWidth,
                height: fittedHeight
            )
        }
        let fittedWidth = availableHeight * imageAspect
        return CGRect(
            x: (canvasSize.width - fittedWidth) / 2,
            y: resolvedInset,
            width: fittedWidth,
            height: availableHeight
        )
    }

    private func phraseTargetGroups() -> [[CGPoint]] {
        HardModeChallengeGeometry.phraseTargetGroups[tracePhraseIndex]
    }

    private func scaled(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        for index in 1..<10 {
            var vertical = Path()
            let x = size.width * CGFloat(index) / 10
            vertical.move(to: CGPoint(x: x, y: 0))
            vertical.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(vertical, with: .color(.white.opacity(0.055)), lineWidth: 1)
        }
        for index in 1..<10 {
            var horizontal = Path()
            let y = size.height * CGFloat(index) / 10
            horizontal.move(to: CGPoint(x: 0, y: y))
            horizontal.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(horizontal, with: .color(.white.opacity(0.055)), lineWidth: 1)
        }
    }

    private func drawDotted(
        points: [CGPoint],
        context: inout GraphicsContext,
        size: CGSize
    ) {
        for point in HardModePathScorer.resample(points: points, spacing: 0.014) {
            let center = scaled(point, in: size)
            let rect = CGRect(x: center.x - 1.8, y: center.y - 1.8, width: 3.6, height: 3.6)
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.66)))
        }
    }

    private var availableSortItems: [Int] {
        shuffledItems.filter { !sortedSlots.compactMap { $0 }.contains($0) }
    }

    private func sortSlot(index: Int, itemID: Int?) -> some View {
        let isIncorrect = incorrectSortSlotIndices.contains(index)

        return Button {
            selectSortSlot(index)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        isIncorrect
                            ? HardModePalette.warning.opacity(0.24)
                            : .white.opacity(0.035)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(
                                isIncorrect
                                    ? HardModePalette.warning
                                    : (selectedSortSlot == index
                                        ? Color.white
                                        : HardModePalette.border),
                                lineWidth: isIncorrect
                                    || selectedSortSlot == index ? 2 : 1
                            )
                    )

                if let itemID {
                    sortTile(itemID)
                        .padding(5)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(HardModePalette.muted.opacity(0.55))
                }
            }
            .frame(height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            itemID.map { "Position \(index + 1), item \(displayRank(for: $0))" }
                ?? "Empty position \(index + 1)"
        )
        .accessibilityValue(isIncorrect ? "Incorrect position" : "")
    }

    private func sortTile(_ itemID: Int) -> some View {
        GeometryReader { proxy in
            let item = HardModeSortChallenge.items[itemID]
            let side = proxy.size.width
            ZStack {
                Circle()
                    .fill(HardModePalette.accent.opacity(0.72))
                    .frame(
                        width: side * item.size,
                        height: side * item.size
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func selectSortSlot(_ index: Int) {
        if let itemID = selectedSortItem {
            if let source = selectedSortSlot {
                guard source != index else {
                    selectedSortItem = nil
                    selectedSortSlot = nil
                    return
                }
                let displaced = sortedSlots[index]
                sortedSlots[index] = itemID
                sortedSlots[source] = displaced
            } else {
                placeSortItem(itemID, in: index)
            }
            selectedSortItem = nil
            selectedSortSlot = nil
            coordinator.clearStepHint()
            return
        }
        if let itemID = sortedSlots[index] {
            selectedSortItem = itemID
            selectedSortSlot = index
        }
    }

    private func placeSortItem(_ itemID: Int, in index: Int) {
        if let existingIndex = sortedSlots.firstIndex(where: { $0 == itemID }) {
            sortedSlots[existingIndex] = sortedSlots[index]
        }
        sortedSlots[index] = itemID
    }

    private var incorrectSortSlotIndices: Set<Int> {
        guard showsOrderValidationErrors else { return [] }
        return HardModeSortChallenge.incorrectSlotIndices(sortedSlots)
    }

    private func displayRank(for itemID: Int) -> String {
        let rank = HardModeSortChallenge.rankedItemIDs.firstIndex(of: itemID).map { $0 + 1 } ?? 0
        return "size rank \(rank)"
    }

    private func timeString(seconds: Int) -> String {
        String(format: "0:%02d", max(0, seconds))
    }
}

private enum HardModePalette {
    static let background = Color(red: 0.015, green: 0.095, blue: 0.064)
    static let card = Color(red: 0.035, green: 0.155, blue: 0.10)
    static let border = Color.white.opacity(0.31)
    static let accent = Color(red: 0.76, green: 0.94, blue: 0.12)
    static let muted = Color(red: 0.70, green: 0.75, blue: 0.65)
    static let warning = Color(red: 1.0, green: 0.55, blue: 0.29)
}
