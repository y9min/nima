import Foundation

struct ControlledNavigationGuard {
    private(set) var generation: UInt64 = 0
    private var blockedRouteTimes: [String: [Date]] = [:]
    private let decisionWindow: TimeInterval
    private let maximumRepeatedBlocks: Int

    init(
        decisionWindow: TimeInterval = 3,
        maximumRepeatedBlocks: Int = 2
    ) {
        self.decisionWindow = decisionWindow
        self.maximumRepeatedBlocks = maximumRepeatedBlocks
    }

    @discardableResult
    mutating func beginNavigation() -> UInt64 {
        generation &+= 1
        return generation
    }

    func isCurrent(_ generation: UInt64) -> Bool {
        generation == self.generation
    }

    mutating func recordBlockedNavigation(
        to url: URL,
        now: Date = Date()
    ) -> Bool {
        let route = "\(url.host?.lowercased() ?? "")\(url.path.lowercased())"
        let cutoff = now.addingTimeInterval(-decisionWindow)
        let recent = (blockedRouteTimes[route] ?? []).filter { $0 >= cutoff }
        let repeated = recent.count + 1 >= maximumRepeatedBlocks
        blockedRouteTimes[route] = Array((recent + [now]).suffix(maximumRepeatedBlocks))
        return repeated
    }

    mutating func resetLoopHistory() {
        blockedRouteTimes.removeAll(keepingCapacity: true)
    }
}
