import XCTest

private typealias XCUIInteractionBlock = @convention(block) () -> Void

@objc private protocol XCUIApplicationPrivateInteractions {
    @objc(_performWithInteractionOptions:block:)
    func performWithInteractionOptions(_ options: UInt, block: XCUIInteractionBlock)

    @objc(setDoesNotHandleUIInterruptions:)
    func setDoesNotHandleUIInterruptions(_ value: Bool)
}

final class TikTokVPNDropUITests: XCTestCase {
    private let skipPreAndPostEventQuiescence: UInt = 1 << 0 | 1 << 1

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTikTokVPNDropScroll() throws {
        let environment = ProcessInfo.processInfo.environment
        let duration = environment.doubleValue(for: "TIKTOK_HARNESS_DURATION", defaultValue: 300)
        let swipeInterval = environment.doubleValue(for: "TIKTOK_HARNESS_SWIPE_INTERVAL", defaultValue: 2.5)
        let swipeMode = environment["TIKTOK_HARNESS_SWIPE_MODE"] ?? "combo"
        let nimaWarmup = environment.doubleValue(for: "TIKTOK_HARNESS_NIMA_WARMUP", defaultValue: 8)
        let tiktokWarmup = environment.doubleValue(for: "TIKTOK_HARNESS_TIKTOK_WARMUP", defaultValue: 6)
        let nimaBundleID = environment["NIMA_BUNDLE_ID"] ?? "so.nima.app"
        let tiktokBundleID = environment["TIKTOK_BUNDLE_ID"] ?? "com.zhiliaoapp.musically"
        let startX = environment.doubleValue(for: "TIKTOK_HARNESS_SWIPE_START_X", defaultValue: 0.50)
        let startY = environment.doubleValue(for: "TIKTOK_HARNESS_SWIPE_START_Y", defaultValue: 0.78)
        let endX = environment.doubleValue(for: "TIKTOK_HARNESS_SWIPE_END_X", defaultValue: 0.50)
        let endY = environment.doubleValue(for: "TIKTOK_HARNESS_SWIPE_END_Y", defaultValue: 0.18)

        let nima = XCUIApplication(bundleIdentifier: nimaBundleID)
        prepareNimaDemoLogin(app: nima)
        enableTikTokVideoBlock(in: nima)
        sleep(seconds: nimaWarmup)

        let tiktok = XCUIApplication(bundleIdentifier: tiktokBundleID)
        tiktok.launch()
        XCTAssertTrue(tiktok.wait(for: .runningForeground, timeout: 15), "TikTok did not reach foreground. Clear login, permission, or first-run prompts on the phone.")
        disableInterruptionHandling(on: tiktok)
        sleep(seconds: tiktokWarmup)

        let startCoordinate = tiktok.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: startY))
        let endCoordinate = tiktok.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: endY))
        let endTime = Date().addingTimeInterval(duration)
        var swipeCount = 0

        while Date() < endTime {
            performWithoutQuiescence(on: tiktok) {
                print("TikTok harness swipe \(swipeCount + 1)")
                self.performTikTokSwipe(mode: swipeMode, app: tiktok, start: startCoordinate, end: endCoordinate)
            }
            swipeCount += 1
            sleep(seconds: swipeInterval)
        }

        XCTContext.runActivity(named: "TikTok VPN drop harness") { activity in
            let attachment = XCTAttachment(string: "duration=\(Int(duration)) swipes=\(swipeCount)")
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    private func prepareNimaDemoLogin(app: XCUIApplication) {
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "Nima did not reach foreground.")

        let homeTikTokIcon = app.descendants(matching: .any)["nima.app.tiktok"].firstMatch
        if homeTikTokIcon.waitForExistence(timeout: 2) {
            return
        }

        let continueButton = app.buttons["nima.landing.go"].firstMatch
        if continueButton.waitForExistence(timeout: 8) {
            continueButton.tap()
        } else {
            XCTFail("Nima landing continue button was not visible.")
        }

        if homeTikTokIcon.waitForExistence(timeout: 4) {
            return
        }

        let emailField = app.textFields["nima.demo.email"].firstMatch
        if emailField.waitForExistence(timeout: 10) {
            emailField.tap()
            emailField.typeText("demo")

            let sendCodeButton = app.buttons["nima.demo.send_code"].firstMatch
            XCTAssertTrue(sendCodeButton.waitForExistence(timeout: 5), "Nima demo login button was not found after entering demo.")
            sendCodeButton.tap()
            XCTAssertTrue(homeTikTokIcon.waitForExistence(timeout: 10), "Nima home did not appear after demo login.")
            return
        }

        XCTFail("Nima did not reach home or demo email screen after tapping Continue.")
    }

    private func enableTikTokVideoBlock(in app: XCUIApplication) {
        let tiktokIcon = app.descendants(matching: .any)["nima.app.tiktok"].firstMatch
        XCTAssertTrue(tiktokIcon.waitForExistence(timeout: 15), "Nima home did not show the TikTok control.")

        if (tiktokIcon.value as? String) != "enabled" {
            tiktokIcon.tap()
        }

        let enabled = waitForAccessibilityValue(
            in: app,
            identifier: "nima.app.tiktok",
            value: "enabled",
            timeout: 5
        )
        XCTAssertTrue(enabled, "Nima TikTok control did not turn on.")
    }

    private func waitForAccessibilityValue(
        in app: XCUIApplication,
        identifier: String,
        value expectedValue: String,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let option = app.descendants(matching: .any)[identifier].firstMatch
            if option.exists, (option.value as? String) == expectedValue {
                return true
            }
            sleep(seconds: 0.25)
        }
        return false
    }

    private func performWithoutQuiescence(on app: XCUIApplication, block: @escaping () -> Void) {
        let object = app as AnyObject
        let selector = NSSelectorFromString("_performWithInteractionOptions:block:")
        guard object.responds(to: selector),
              let privateApp = object as? XCUIApplicationPrivateInteractions else {
            block()
            return
        }
        privateApp.performWithInteractionOptions(skipPreAndPostEventQuiescence, block: block)
    }

    private func disableInterruptionHandling(on app: XCUIApplication) {
        let object = app as AnyObject
        let selector = NSSelectorFromString("setDoesNotHandleUIInterruptions:")
        guard object.responds(to: selector),
              let privateApp = object as? XCUIApplicationPrivateInteractions else {
            return
        }
        privateApp.setDoesNotHandleUIInterruptions(true)
    }

    private func performTikTokSwipe(
        mode: String,
        app: XCUIApplication,
        start: XCUICoordinate,
        end: XCUICoordinate
    ) {
        switch mode {
        case "app":
            app.swipeUp(velocity: .fast)
        case "drag":
            dragFeed(start: start, end: end)
        case "scroll":
            start.scroll(byDeltaX: 0, deltaY: -700)
        default:
            app.swipeUp(velocity: .fast)
            Thread.sleep(forTimeInterval: 0.15)
            dragFeed(start: start, end: end)
        }
    }

    private func dragFeed(start: XCUICoordinate, end: XCUICoordinate) {
        start.press(
            forDuration: 0.04,
            thenDragTo: end,
            withVelocity: .fast,
            thenHoldForDuration: 0.02
        )
    }

    private func sleep(seconds: TimeInterval) {
        guard seconds > 0 else { return }
        Thread.sleep(forTimeInterval: seconds)
    }
}

final class NimaAdaptiveLayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCompactOnboardingContentRemainsReachable() throws {
        let app = XCUIApplication(bundleIdentifier: "so.nima.app")
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_GB"]
        app.launch()

        let start = app.buttons["onboarding.splash.start"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 15), "The onboarding start button is not visible.")
        assertInsideScreen(start, app: app)
        attachScreenshot(named: "01-splash", app: app)
        start.tap()

        let nameField = app.textFields["onboarding.name.input"].firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "The name field is not visible.")
        nameField.tap()
        nameField.typeText("Layout Test")

        let nameContinue = app.buttons["onboarding.name.continue"].firstMatch
        makeReachable(nameContinue, in: app)
        XCTAssertTrue(nameContinue.isHittable, "The name Continue button cannot be reached.")
        nameContinue.tap()

        let habit = app.buttons["Ignoring people around me"].firstMatch
        XCTAssertTrue(habit.waitForExistence(timeout: 5), "The first habit row is not visible.")
        habit.tap()

        let habitsContinue = app.buttons["onboarding.habits.continue"].firstMatch
        makeReachable(habitsContinue, in: app)
        XCTAssertTrue(habitsContinue.isHittable, "The habits Continue button cannot be reached on a compact screen.")
        assertInsideScreen(habitsContinue, app: app)
        attachScreenshot(named: "02-habits-bottom", app: app)
        habitsContinue.tap()

        let agePicker = app.pickerWheels.firstMatch
        XCTAssertTrue(agePicker.waitForExistence(timeout: 5), "The age picker is not visible.")
        agePicker.adjust(toPickerWheelValue: "19")

        let ageContinue = app.buttons["onboarding.age.continue"].firstMatch
        makeReachable(ageContinue, in: app)
        XCTAssertTrue(ageContinue.isHittable, "The age Continue button cannot be reached.")
        ageContinue.tap()

        let appChoice = app.buttons["Instagram"].firstMatch
        XCTAssertTrue(appChoice.waitForExistence(timeout: 5), "The app selection rows are not visible.")
        appChoice.tap()

        let appsContinue = app.buttons["onboarding.apps.continue"].firstMatch
        makeReachable(appsContinue, in: app)
        XCTAssertTrue(appsContinue.isHittable, "The app selection Continue button cannot be reached on a compact screen.")
        assertInsideScreen(appsContinue, app: app)
        attachScreenshot(named: "03-apps-bottom", app: app)
    }

    private func makeReachable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable, app.frame.insetBy(dx: -1, dy: -1).contains(element.frame) {
                return
            }
            app.swipeUp()
        }
    }

    private func assertInsideScreen(_ element: XCUIElement, app: XCUIApplication) {
        let screen = app.frame
        let frame = element.frame
        XCTAssertGreaterThanOrEqual(frame.minX, screen.minX - 1)
        XCTAssertGreaterThanOrEqual(frame.minY, screen.minY - 1)
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX + 1)
        XCTAssertLessThanOrEqual(frame.maxY, screen.maxY + 1)
    }

    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

final class NimaReviewerJourneyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testExpiredReviewAccountCompletesGuidanceAndReachesPaywall() throws {
        let app = XCUIApplication(bundleIdentifier: "so.nima.app")
        app.launchArguments += [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_GB",
            "-NimaSimulateExpiredReviewSubscription",
        ]

        addUIInterruptionMonitor(withDescription: "Nima permissions") { alert in
            for label in ["Allow", "OK", "Continue"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        app.launch()
        completeOnboarding(in: app)

        let guide = app.descendants(matching: .any)["guided_onboarding.modal"].firstMatch
        XCTAssertTrue(guide.waitForExistence(timeout: 15), "The guided onboarding modal did not appear after review login.")

        let settings = app.buttons["settings"].firstMatch
        XCTAssertTrue(settings.exists, "The Settings tab was not present during guided onboarding.")
        XCTAssertFalse(settings.isEnabled, "Settings must remain locked until the reviewer reaches the paywall.")

        let nextGuideSlide = app.buttons["Next guide slide"].firstMatch
        XCTAssertTrue(nextGuideSlide.waitForExistence(timeout: 5))
        nextGuideSlide.tap()
        XCTAssertTrue(nextGuideSlide.waitForExistence(timeout: 5))
        nextGuideSlide.tap()

        let finishGuide = app.buttons["guided_onboarding.done"].firstMatch
        XCTAssertTrue(finishGuide.waitForExistence(timeout: 5), "The guided onboarding completion button did not appear.")
        finishGuide.tap()

        let tikTok = app.descendants(matching: .any)["nima.app.tiktok"].firstMatch
        XCTAssertTrue(tikTok.waitForExistence(timeout: 8), "The TikTok blocker was not available for guided practice.")
        XCTAssertFalse(settings.isEnabled, "Settings unlocked before guided practice completed.")
        tikTok.tap()

        let openAppPrompt = app.descendants(matching: .any)["guided_practice.open_app_prompt"].firstMatch
        XCTAssertTrue(openAppPrompt.waitForExistence(timeout: 10), "Guided practice did not reach the external-app prompt.")

        let skipPractice = app.buttons["guided_practice.skip_external_app"].firstMatch
        XCTAssertTrue(skipPractice.waitForExistence(timeout: 5), "The reviewer-safe Skip practice action was missing.")
        skipPractice.tap()

        let startWindowsGuide = app.buttons["guided_windows.home.start"].firstMatch
        XCTAssertTrue(startWindowsGuide.waitForExistence(timeout: 8), "The guided windows step did not begin.")
        XCTAssertFalse(settings.isEnabled, "Settings unlocked before guided windows completed.")
        startWindowsGuide.tap()

        let closeEditor = app.buttons["guided_windows.editor.close"].firstMatch
        XCTAssertTrue(closeEditor.waitForExistence(timeout: 8), "The guided window editor did not open.")
        closeEditor.tap()

        let windowsReady = app.buttons["guided_windows.ready_continue"].firstMatch
        XCTAssertTrue(windowsReady.waitForExistence(timeout: 8), "The guided windows completion screen did not appear.")
        windowsReady.tap()

        let reviewContinue = app.buttons["guided_practice.review_continue"].firstMatch
        XCTAssertTrue(reviewContinue.waitForExistence(timeout: 8), "The final guided-practice screen did not appear.")
        reviewContinue.tap()
        dismissStoreReviewPromptIfPresent(in: app)
        XCTAssertTrue(reviewContinue.waitForExistence(timeout: 5))
        reviewContinue.tap()

        let paywall = app.descendants(matching: .any)["subscription.paywall"].firstMatch
        XCTAssertTrue(paywall.waitForExistence(timeout: 15), "The expired review account did not reach the subscription paywall.")
        XCTAssertFalse(app.buttons["settings"].exists, "Settings remained reachable over the paywall.")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "reviewer-expired-account-paywall"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func completeOnboarding(in app: XCUIApplication) {
        tap("onboarding.splash.start", in: app)

        let name = app.textFields["onboarding.name.input"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("App Review")
        tap("onboarding.name.continue", in: app)

        tapButton(label: "Ignoring people around me", in: app)
        tap("onboarding.habits.continue", in: app)

        let age = app.pickerWheels.firstMatch
        XCTAssertTrue(age.waitForExistence(timeout: 5))
        age.adjust(toPickerWheelValue: "25")
        tap("onboarding.age.continue", in: app)

        tapButton(label: "Instagram", in: app)
        tap("onboarding.apps.continue", in: app)

        let phoneSlider = app.descendants(matching: .any)["onboarding.phone.slider"].firstMatch
        XCTAssertTrue(phoneSlider.waitForExistence(timeout: 5))
        phoneSlider.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)).tap()
        tap("onboarding.phone.continue", in: app)

        tap("onboarding.bad-news.continue", in: app, timeout: 15)
        tap("onboarding.good-news.continue", in: app, timeout: 15)
        tap("onboarding.stay-connected.continue", in: app)
        tap("onboarding.vpn.continue", in: app)
        tap("onboarding.privacy-checklist.continue", in: app)
        tap("onboarding.vpn-data.continue", in: app)
        handlePermissionAlertIfPresent(app: app)

        tap("onboarding.notifications.continue", in: app, timeout: 10)
        handlePermissionAlertIfPresent(app: app)

        let email = app.textFields["onboarding.email.input"].firstMatch
        if !email.waitForExistence(timeout: 2) {
            tapButton(label: "Already have an account? Log in", in: app, timeout: 10)
        }
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("review@nima.so")
        tap("onboarding.email.send_link", in: app)
    }

    private func tap(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval = 8) {
        let element = app.buttons[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(identifier) did not appear.")
        makeReachable(element, in: app)
        XCTAssertTrue(element.isHittable, "\(identifier) was not hittable.")
        element.tap()
    }

    private func tapButton(label: String, in app: XCUIApplication, timeout: TimeInterval = 8) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "\(label) did not appear.")
        makeReachable(button, in: app)
        XCTAssertTrue(button.isHittable, "\(label) was not hittable.")
        button.tap()
    }

    private func makeReachable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
    }

    private func handlePermissionAlertIfPresent(app: XCUIApplication) {
        app.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 2) else { return }
        for label in ["Allow", "OK", "Continue"] where alert.buttons[label].exists {
            alert.buttons[label].tap()
            return
        }
    }

    private func dismissStoreReviewPromptIfPresent(in app: XCUIApplication) {
        for label in ["Not Now", "Cancel"] {
            let button = app.buttons[label].firstMatch
            if button.waitForExistence(timeout: 1) {
                button.tap()
                return
            }
        }
    }
}

private extension Dictionary where Key == String, Value == String {
    func doubleValue(for key: String, defaultValue: Double) -> Double {
        guard let value = self[key], let parsed = Double(value) else {
            return defaultValue
        }
        return parsed
    }
}
