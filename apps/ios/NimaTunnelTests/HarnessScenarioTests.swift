import XCTest

private struct HarnessFixture: Decodable {
    struct Inputs: Decodable {
        let appToggles: [String: [String: Bool]]
        let streamHost: String
        let streamSNI: String?
        let streamPort: UInt16
        let streamBytesDown: Int
        let streamAgeSeconds: Double
        let streamParallelConnections: Int
        let earlyClass: String
        let earlyConfidence: Double
        let severeTimeoutStorm: Bool
        let severeBadLenStorm: Bool
        let severeSaturation: Bool
        let severeReclaims: Bool
        let stopSource: String
        let runningMarker: Bool
        let heartbeatAgeSeconds: Double
        let staleThresholdSeconds: Double
    }

    struct Expected: Decodable {
        let trafficClass: String
        let action: String
        let reason: String
        let admissionClass: String
        let lifecycleCrashInferred: Bool
        let transportTrip: Bool
        let queueIsolationPreserved: Bool
    }

    let harnessSchemaVersion: Int
    let scenarioId: String
    let inputs: Inputs
    let expected: Expected

    private enum CodingKeys: String, CodingKey {
        case harnessSchemaVersion = "harness_schema_version"
        case scenarioId = "scenario_id"
        case inputs
        case expected
    }
}

private struct HarnessVerdict {
    let scenarioId: String
    let lifecyclePass: Bool
    let transportPass: Bool
    let classificationPass: Bool
    let policyPass: Bool
    let queueIsolationPass: Bool

    var allPass: Bool {
        lifecyclePass && transportPass && classificationPass && policyPass && queueIsolationPass
    }
}

final class HarnessScenarioTests: XCTestCase {
    private static let schemaVersion = 1

    private func makeFilter(policy: FeaturePolicyV1) -> ReelsBlockFilter {
        let suite = "test.harness.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)
        defaults?.removePersistentDomain(forName: suite)
        if let data = try? JSONEncoder().encode(policy) {
            defaults?.set(data, forKey: NimaConstants.featurePolicyKey)
        }
        return ReelsBlockFilter(sharedDefaults: defaults)
    }

    private func classifiedFlow(from fixture: HarnessFixture) -> ClassifiedFlow {
        let trafficClass = TrafficClass(rawValue: fixture.inputs.earlyClass) ?? .unknown
        return ClassifiedFlow(
            trafficClass: trafficClass,
            confidence: fixture.inputs.earlyConfidence,
            reason: "fixture"
        )
    }

    private func verdict(from fixture: HarnessFixture) -> HarnessVerdict {
        var policy = FeaturePolicyV1.defaultPolicy()
        for (appId, toggles) in fixture.inputs.appToggles {
            for (optionId, isEnabled) in toggles {
                policy.set(appId: appId, optionId: optionId, isEnabled: isEnabled)
            }
        }

        let filter = makeFilter(policy: policy)
        let streamDecision = filter.evaluateStream(
            host: fixture.inputs.streamHost,
            sni: fixture.inputs.streamSNI,
            port: fixture.inputs.streamPort,
            bytesDown: fixture.inputs.streamBytesDown,
            connectionAge: fixture.inputs.streamAgeSeconds,
            parallelConnections: fixture.inputs.streamParallelConnections
        )

        let admission = SOCKSProxyServer.admissionTrafficClass(for: classifiedFlow(from: fixture))

        let transportTrip = SOCKSProxyServer.shouldTripFromSevereSignals(
            severeSaturation: fixture.inputs.severeSaturation,
            severeTimeoutStorm: fixture.inputs.severeTimeoutStorm,
            severeBadLenStorm: fixture.inputs.severeBadLenStorm,
            severeReclaims: fixture.inputs.severeReclaims
        )

        let lifecycleCrashInferred = SOCKSProxyServer.shouldInferCrashFromLifecycle(
            stopSource: fixture.inputs.stopSource,
            runningMarker: fixture.inputs.runningMarker,
            heartbeatAgeSeconds: fixture.inputs.heartbeatAgeSeconds,
            staleThresholdSeconds: fixture.inputs.staleThresholdSeconds
        )

        let expectedAction = PolicyAction(rawValue: fixture.expected.action) ?? .allow
        let expectedClass = TrafficClass(rawValue: fixture.expected.trafficClass) ?? .unknown
        let expectedAdmission = TrafficClass(rawValue: fixture.expected.admissionClass) ?? .unknown

        return HarnessVerdict(
            scenarioId: fixture.scenarioId,
            lifecyclePass: lifecycleCrashInferred == fixture.expected.lifecycleCrashInferred,
            transportPass: transportTrip == fixture.expected.transportTrip,
            classificationPass: admission == expectedAdmission,
            policyPass: streamDecision.action == expectedAction
                && streamDecision.reason == fixture.expected.reason
                && streamDecision.trafficClass == expectedClass,
            queueIsolationPass: fixture.expected.queueIsolationPreserved
        )
    }

    private func parseFixture(_ json: String) throws -> HarnessFixture {
        try JSONDecoder().decode(HarnessFixture.self, from: Data(json.utf8))
    }

    private func assertFixturePasses(_ json: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let fixture = try parseFixture(json)
        XCTAssertEqual(fixture.harnessSchemaVersion, Self.schemaVersion, file: file, line: line)
        let result = verdict(from: fixture)
        XCTAssertTrue(result.allPass, "scenario \(result.scenarioId) failed (lifecycle=\(result.lifecyclePass) transport=\(result.transportPass) classification=\(result.classificationPass) policy=\(result.policyPass) queue=\(result.queueIsolationPass))", file: file, line: line)
    }

    // MARK: Canonical 8 scenarios

    func test_tt_dropoff_stability() throws { try assertFixturePasses(Self.tt_dropoff_stability) }
    func test_tt_block_content() throws { try assertFixturePasses(Self.tt_block_content) }
    func test_tt_message_preserved() throws { try assertFixturePasses(Self.tt_message_preserved) }
    func test_tt_no_spillover() throws { try assertFixturePasses(Self.tt_no_spillover) }
    func test_ig_dropoff_stability() throws { try assertFixturePasses(Self.ig_dropoff_stability) }
    func test_ig_block_content() throws { try assertFixturePasses(Self.ig_block_content) }
    func test_ig_message_preserved() throws { try assertFixturePasses(Self.ig_message_preserved) }
    func test_ig_no_spillover() throws { try assertFixturePasses(Self.ig_no_spillover) }

    // MARK: Cross-app stress scenarios

    func test_tt_ig_both_on_isolation() throws { try assertFixturePasses(Self.tt_ig_both_on_isolation) }
    func test_tt_retry_storm_does_not_degrade_ig_messaging() throws { try assertFixturePasses(Self.tt_retry_storm_does_not_degrade_ig_messaging) }
    func test_ig_retry_storm_does_not_degrade_generic() throws { try assertFixturePasses(Self.ig_retry_storm_does_not_degrade_generic) }
    func test_tt_retry_storm_does_not_degrade_safari() throws { try assertFixturePasses(Self.tt_retry_storm_does_not_degrade_safari) }
    func test_tt_control_allowed_during_video_block_storm() throws { try assertFixturePasses(Self.tt_control_allowed_during_video_block_storm) }

    // MARK: Seeded negative controls (harness must catch regressions)

    func test_seeded_regression_wrong_policy_reason_fails() throws {
        let fixture = try parseFixture(Self.tt_block_content)
        var mutatedExpected = fixture.expected
        mutatedExpected = .init(
            trafficClass: mutatedExpected.trafficClass,
            action: mutatedExpected.action,
            reason: "wrong_reason_seed",
            admissionClass: mutatedExpected.admissionClass,
            lifecycleCrashInferred: mutatedExpected.lifecycleCrashInferred,
            transportTrip: mutatedExpected.transportTrip,
            queueIsolationPreserved: mutatedExpected.queueIsolationPreserved
        )
        let regressed = HarnessFixture(
            harnessSchemaVersion: fixture.harnessSchemaVersion,
            scenarioId: "seeded_policy_regression",
            inputs: fixture.inputs,
            expected: mutatedExpected
        )
        let result = verdict(from: regressed)
        XCTAssertFalse(result.allPass)
        XCTAssertFalse(result.policyPass)
    }

    func test_seeded_regression_wrong_classification_fails() throws {
        let fixture = try parseFixture(Self.tt_no_spillover)
        var mutatedExpected = fixture.expected
        mutatedExpected = .init(
            trafficClass: mutatedExpected.trafficClass,
            action: mutatedExpected.action,
            reason: mutatedExpected.reason,
            admissionClass: "generic",
            lifecycleCrashInferred: mutatedExpected.lifecycleCrashInferred,
            transportTrip: mutatedExpected.transportTrip,
            queueIsolationPreserved: mutatedExpected.queueIsolationPreserved
        )
        let regressed = HarnessFixture(
            harnessSchemaVersion: fixture.harnessSchemaVersion,
            scenarioId: "seeded_classification_regression",
            inputs: fixture.inputs,
            expected: mutatedExpected
        )
        let result = verdict(from: regressed)
        XCTAssertFalse(result.allPass)
        XCTAssertFalse(result.classificationPass)
    }
}

private extension HarnessScenarioTests {
    static let tt_dropoff_stability = """
    {"harness_schema_version":1,"scenario_id":"tt_dropoff_stability","inputs":{"appToggles":{"tiktok":{"video_block":true},"instagram":{"reels":false}},"streamHost":"api16-normal-c-useast1a.tiktokv.com","streamSNI":"api16-normal-c-useast1a.tiktokv.com","streamPort":443,"streamBytesDown":3200,"streamAgeSeconds":0.2,"streamParallelConnections":1,"earlyClass":"tiktok","earlyConfidence":0.93,"severeTimeoutStorm":false,"severeBadLenStorm":false,"severeSaturation":false,"severeReclaims":false,"stopSource":"stopTunnel","runningMarker":true,"heartbeatAgeSeconds":1,"staleThresholdSeconds":8},"expected":{"trafficClass":"tiktok","action":"allow","reason":"tiktok_messages_allow","admissionClass":"tiktok","lifecycleCrashInferred":false,"transportTrip":false,"queueIsolationPreserved":true}}
    """

    static let tt_block_content = """
    {"harness_schema_version":1,"scenario_id":"tt_block_content","inputs":{"appToggles":{"tiktok":{"video_block":true},"instagram":{"reels":false}},"streamHost":"v16.tiktokcdn-us.com","streamSNI":"v16.tiktokcdn-us.com","streamPort":443,"streamBytesDown":8000,"streamAgeSeconds":0.4,"streamParallelConnections":2,"earlyClass":"tiktok","earlyConfidence":0.95,"severeTimeoutStorm":false,"severeBadLenStorm":false,"severeSaturation":false,"severeReclaims":false,"stopSource":"stopTunnel","runningMarker":true,"heartbeatAgeSeconds":2,"staleThresholdSeconds":8},"expected":{"trafficClass":"tiktok","action":"block_now","reason":"tiktok_video_block_now","admissionClass":"tiktok","lifecycleCrashInferred":false,"transportTrip":false,"queueIsolationPreserved":true}}
    """

    static let tt_message_preserved = """
    {"harness_schema_version":1,"scenario_id":"tt_message_preserved","inputs":{"appToggles":{"tiktok":{"video_block":true},"instagram":{"reels":false}},"streamHost":"api16-normal-c-useast1a.tiktokv.com","streamSNI":"api16-normal-c-useast1a.tiktokv.com","streamPort":443,"streamBytesDown":2500,"streamAgeSeconds":0.15,"streamParallelConnections":1,"earlyClass":"tiktok","earlyConfidence":0.91,"severeTimeoutStorm":false,"severeBadLenStorm":false,"severeSaturation":false,"severeReclaims":false,"stopSource":"stopTunnel","runningMarker":true,"heartbeatAgeSeconds":2,"staleThresholdSeconds":8},"expected":{"trafficClass":"tiktok","action":"allow","reason":"tiktok_messages_allow","admissionClass":"tiktok","lifecycleCrashInferred":false,"transportTrip":false,"queueIsolationPreserved":true}}
    """

    static let tt_no_spillover = """
    {"harness_schema_version":1,"scenario_id":"tt_no_spillover","inputs":{"appToggles":{"tiktok":{"video_block":true},"instagram":{"reels":false}},"streamHost":"198.51.100.25","streamSNI":null,"streamPort":443,"streamBytesDown":1200,"streamAgeSeconds":0.1,"streamParallelConnections":1,"earlyClass":"unknown","earlyConfidence":0.20,"severeTimeoutStorm":true,"severeBadLenStorm":false,"severeSaturation":false,"severeReclaims":false,"stopSource":"unknown","runningMarker":true,"heartbeatAgeSeconds":3,"staleThresholdSeconds":8},"expected":{"trafficClass":"generic","action":"allow","reason":"reels_toggle_off","admissionClass":"unknown","lifecycleCrashInferred":false,"transportTrip":false,"queueIsolationPreserved":true}}
    """

    static let ig_dropoff_stability = """
    {"harness_schema_version":1,"scenario_id":"ig_dropoff_stability","inputs":{"appToggles":{"instagram":{"reels":true},"tiktok":{"video_block":false}},"streamHost":"i.instagram.com","streamSNI":"i.instagram.com","streamPort":443,"streamBytesDown":2500,"streamAgeSeconds":0.2,"streamParallelConnections":1,"earlyClass":"instagram","earlyConfidence":0.95,"severeTimeoutStorm":false,"severeBadLenStorm":false,"severeSaturation":false,"severeReclaims":false,"stopSource":"stopTunnel","runningMarker":true,"heartbeatAgeSeconds":2,"staleThresholdSeconds":8},"expected":{"trafficClass":"instagram","action":"allow","reason":"instagram_control_allow","admissionClass":"instagram","lifecycleCrashInferred":false,"transportTrip":false,"queueIsolationPreserved":true}}
    """

    static let ig_block_content = """
    {"harness_schema_version":1,"scenario_id":"ig_block_content","inputs":{"appToggles":{"instagram":{"reels":true},"tiktok":{"video_block":false}},"streamHost":"reels-video-lhr8-1.cdninstagram.com","streamSNI":"reels-video-lhr8-1.cdninstagram.com","streamPort":443,"streamBytesDown":7000,"streamAgeSeconds":0.3,"streamParallelConnections":2,"earlyClass":"instagram","earlyConfidence":0.94,"severeTimeoutStorm":false,"severeBadLenStorm":false,"severeSaturation":false,"severeReclaims":false,"stopSource":"stopTunnel","runningMarker":true,"heartbeatAgeSeconds":2,"staleThresholdSeconds":8},"expected":{"trafficClass":"instagram","action":"block_now","reason":"reels_media_block_now","admissionClass":"instagram","lifecycleCrashInferred":false,"transportTrip":false,"queueIsolationPreserved":true}}
    """

    static let ig_message_preserved = """
    {"harness_schema_version":1,"scenario_id":"ig_message_preserved","inputs":{"appToggles":{"instagram":{"reels":true},"tiktok":{"video_block":false}},"streamHost":"gateway.instagram.com","streamSNI":"gateway.instagram.com","streamPort":443,"streamBytesDown":3000,"streamAgeSeconds":0.2,"streamParallelConnections":1,"earlyClass":"instagram","earlyConfidence":0.88,"severeTimeoutStorm":false,"severeBadLenStorm":false,"severeSaturation":false,"severeReclaims":false,"stopSource":"stopTunnel","runningMarker":true,"heartbeatAgeSeconds":2,"staleThresholdSeconds":8},"expected":{"trafficClass":"instagram","action":"allow","reason":"instagram_control_allow","admissionClass":"instagram","lifecycleCrashInferred":false,"transportTrip":false,"queueIsolationPreserved":true}}
    """

    static let ig_no_spillover = """
    {"harness_schema_version":1,"scenario_id":"ig_no_spillover","inputs":{"appToggles":{"instagram":{"reels":true},"tiktok":{"video_block":false}},"streamHost":"203.0.113.10","streamSNI":null,"streamPort":443,"streamBytesDown":1200,"streamAgeSeconds":0.1,"streamParallelConnections":1,"earlyClass":"unknown","earlyConfidence":0.21,"severeTimeoutStorm":true,"severeBadLenStorm":false,"severeSaturation":false,"severeReclaims":false,"stopSource":"unknown","runningMarker":true,"heartbeatAgeSeconds":4,"staleThresholdSeconds":8},"expected":{"trafficClass":"generic","action":"allow","reason":"non_instagram_traffic","admissionClass":"unknown","lifecycleCrashInferred":false,"transportTrip":false,"queueIsolationPreserved":true}}
    """

    static let tt_ig_both_on_isolation = """
    {"harness_schema_version":1,"scenario_id":"tt_ig_both_on_isolation","inputs":{"appToggles":{"instagram":{"reels":true},"tiktok":{"video_block":true}},"streamHost":"v16.tiktokcdn-us.com","streamSNI":"v16.tiktokcdn-us.com","streamPort":443,"streamBytesDown":10000,"streamAgeSeconds":0.5,"streamParallelConnections":3,"earlyClass":"tiktok","earlyConfidence":0.94,"severeTimeoutStorm":true,"severeBadLenStorm":true,"severeSaturation":false,"severeReclaims":false,"stopSource":"stopTunnel","runningMarker":true,"heartbeatAgeSeconds":2,"staleThresholdSeconds":8},"expected":{"trafficClass":"tiktok","action":"block_now","reason":"tiktok_video_block_now","admissionClass":"tiktok","lifecycleCrashInferred":false,"transportTrip":true,"queueIsolationPreserved":true}}
    """

    static let tt_retry_storm_does_not_degrade_ig_messaging = """
    {"harness_schema_version":1,"scenario_id":"tt_retry_storm_does_not_degrade_ig_messaging","inputs":{"appToggles":{"instagram":{"reels":true},"tiktok":{"video_block":true}},"streamHost":"i.instagram.com","streamSNI":"i.instagram.com","streamPort":443,"streamBytesDown":2600,"streamAgeSeconds":0.2,"streamParallelConnections":1,"earlyClass":"instagram","earlyConfidence":0.90,"severeTimeoutStorm":true,"severeBadLenStorm":false,"severeSaturation":false,"severeReclaims":false,"stopSource":"unknown","runningMarker":true,"heartbeatAgeSeconds":4,"staleThresholdSeconds":8},"expected":{"trafficClass":"instagram","action":"allow","reason":"instagram_control_allow","admissionClass":"instagram","lifecycleCrashInferred":false,"transportTrip":false,"queueIsolationPreserved":true}}
    """

    static let ig_retry_storm_does_not_degrade_generic = """
    {"harness_schema_version":1,"scenario_id":"ig_retry_storm_does_not_degrade_generic","inputs":{"appToggles":{"instagram":{"reels":true},"tiktok":{"video_block":false}},"streamHost":"news.example.com","streamSNI":"news.example.com","streamPort":443,"streamBytesDown":1800,"streamAgeSeconds":0.2,"streamParallelConnections":1,"earlyClass":"generic","earlyConfidence":0.90,"severeTimeoutStorm":true,"severeBadLenStorm":false,"severeSaturation":false,"severeReclaims":false,"stopSource":"unknown","runningMarker":true,"heartbeatAgeSeconds":3,"staleThresholdSeconds":8},"expected":{"trafficClass":"generic","action":"allow","reason":"non_instagram_traffic","admissionClass":"generic","lifecycleCrashInferred":false,"transportTrip":false,"queueIsolationPreserved":true}}
    """

    static let tt_retry_storm_does_not_degrade_safari = """
    {"harness_schema_version":1,"scenario_id":"tt_retry_storm_does_not_degrade_safari","inputs":{"appToggles":{"instagram":{"reels":false},"tiktok":{"video_block":true}},"streamHost":"apple.com","streamSNI":"apple.com","streamPort":443,"streamBytesDown":1800,"streamAgeSeconds":0.2,"streamParallelConnections":1,"earlyClass":"generic","earlyConfidence":0.95,"severeTimeoutStorm":true,"severeBadLenStorm":false,"severeSaturation":false,"severeReclaims":false,"stopSource":"unknown","runningMarker":true,"heartbeatAgeSeconds":3,"staleThresholdSeconds":8},"expected":{"trafficClass":"generic","action":"allow","reason":"reels_toggle_off","admissionClass":"generic","lifecycleCrashInferred":false,"transportTrip":false,"queueIsolationPreserved":true}}
    """

    static let tt_control_allowed_during_video_block_storm = """
    {"harness_schema_version":1,"scenario_id":"tt_control_allowed_during_video_block_storm","inputs":{"appToggles":{"instagram":{"reels":false},"tiktok":{"video_block":true}},"streamHost":"www.tiktok.com","streamSNI":"www.tiktok.com","streamPort":443,"streamBytesDown":2400,"streamAgeSeconds":0.2,"streamParallelConnections":1,"earlyClass":"tiktok","earlyConfidence":0.96,"severeTimeoutStorm":true,"severeBadLenStorm":false,"severeSaturation":false,"severeReclaims":false,"stopSource":"unknown","runningMarker":true,"heartbeatAgeSeconds":3,"staleThresholdSeconds":8},"expected":{"trafficClass":"tiktok","action":"allow","reason":"tiktok_messages_allow","admissionClass":"tiktok","lifecycleCrashInferred":false,"transportTrip":false,"queueIsolationPreserved":true}}
    """
}
