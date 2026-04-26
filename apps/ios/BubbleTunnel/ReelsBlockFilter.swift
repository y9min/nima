import Foundation

final class ReelsBlockFilter: ConnectionFilter {

    private let sharedDefaults = UserDefaults(suiteName: BubbleConstants.appGroupID)

    var isEnabled: Bool {
        guard let defaults = sharedDefaults else { return true }
        guard defaults.object(forKey: BubbleConstants.blockReelsEnabledKey) != nil else {
            return true
        }
        return defaults.bool(forKey: BubbleConstants.blockReelsEnabledKey)
    }

    // MARK: - ConnectionFilter

    func shouldAllow(host: String, port: UInt16) -> FilterDecision {
        guard isEnabled else { return .allow }
        let lowerHost = host.lowercased()
        if looksLikeDomain(lowerHost),
           let threshold = streamBlockThreshold(for: lowerHost),
           threshold == 0 {
            return .block
        }
        return .allow
    }

    func shouldBlockUDP(host: String, port: UInt16) -> Bool {
        guard isEnabled else { return false }
        guard isStrictUDPBlockingEnabled else { return false }
        guard port == 443 else { return false }

        let lowerHost = host.lowercased()

        // If host is a domain, block likely Instagram media domains in strict mode.
        if looksLikeDomain(lowerHost) {
            for (domain, threshold) in loadDomainThresholds() where threshold != BubbleConstants.noLimitThreshold {
                if lowerHost.contains(domain.lowercased()) {
                    return true
                }
            }
            if lowerHost.contains("instagram.com") || lowerHost.contains("facebook.com") {
                return true
            }
        }

        return false
    }

    /// Returns the byte threshold for a given SNI domain.
    /// - Returns `nil` if no blocking rule matches (allow unlimited).
    /// - Returns `0` to block immediately.
    /// - Returns `>0` to block after that many bytes.
    func streamBlockThreshold(for sni: String) -> Int? {
        guard isEnabled else { return nil }

        let thresholds = loadDomainThresholds()
        let lower = sni.lowercased()

        // Check each tracked domain — match if the SNI contains it
        for (domain, threshold) in thresholds {
            if lower.contains(domain.lowercased()) {
                if threshold == BubbleConstants.noLimitThreshold {
                    return nil // no limit for this domain
                }
                return threshold
            }
        }

        return nil // no matching rule → allow
    }

    func isStreamBlockTarget(_ domain: String) -> Bool {
        return streamBlockThreshold(for: domain) != nil
    }

    // MARK: - Private

    private func loadDomainThresholds() -> [String: Int] {
        var thresholds = BubbleConstants.reelsDemoDomainThresholds
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: BubbleConstants.domainThresholdsKey),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return thresholds
        }
        thresholds.merge(dict) { _, new in new }
        return thresholds
    }

    private var isStrictUDPBlockingEnabled: Bool {
        guard let defaults = sharedDefaults else { return false }
        guard defaults.object(forKey: BubbleConstants.strictUDPBlockEnabledKey) != nil else {
            return false
        }
        return defaults.bool(forKey: BubbleConstants.strictUDPBlockEnabledKey)
    }

    private func looksLikeDomain(_ host: String) -> Bool {
        guard host.contains(".") else { return false }
        guard !host.contains(":") else { return false } // likely IPv6
        return host.rangeOfCharacter(from: .letters) != nil
    }
}
