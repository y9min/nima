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

private extension Dictionary where Key == String, Value == String {
    func doubleValue(for key: String, defaultValue: Double) -> Double {
        guard let value = self[key], let parsed = Double(value) else {
            return defaultValue
        }
        return parsed
    }
}
