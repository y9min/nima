import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let defaults = UserDefaults(suiteName: NimaConstants.appGroupID)

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity.rawValue.hasPrefix("nima.instagram.") else { return }
        let selection = loadSelection()
        guard !selection.applicationTokens.isEmpty else { return }
        store(for: activity).shield.applications = selection.applicationTokens
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity.rawValue.hasPrefix("nima.instagram.") else { return }
        store(for: activity).shield.applications = nil
    }

    private func loadSelection() -> FamilyActivitySelection {
        guard let data = defaults?.data(forKey: NimaConstants.instagramFamilySelectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return FamilyActivitySelection()
        }
        return selection
    }

    private func store(for activity: DeviceActivityName) -> ManagedSettingsStore {
        ManagedSettingsStore(named: .init(activity.rawValue))
    }
}
