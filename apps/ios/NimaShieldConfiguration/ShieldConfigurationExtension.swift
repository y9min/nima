import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration(for: application)
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration(for: application)
    }

    private func makeConfiguration(for application: Application) -> ShieldConfiguration {
        if let token = application.token,
           let kind = AppControlRuleState.activeKind(for: token) {
            return ShieldConfiguration(
                backgroundBlurStyle: .systemUltraThinMaterialDark,
                backgroundColor: UIColor(red: 0.035, green: 0.047, blue: 0.039, alpha: 0.96),
                icon: UIImage(named: "AppIcon-1024x1024"),
                title: .init(text: kind == .blocked ? "App blocked" : "Daily limit reached", color: .white),
                subtitle: .init(
                    text: kind == .blocked ? "You blocked this app in Nima" : "Your time for this app is up today",
                    color: UIColor.white.withAlphaComponent(0.68)
                ),
                primaryButtonLabel: .init(text: "Close app", color: .white),
                primaryButtonBackgroundColor: UIColor(red: 0.20, green: 0.46, blue: 0.30, alpha: 1)
            )
        }
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.035, green: 0.047, blue: 0.039, alpha: 0.96),
            icon: UIImage(named: "AppIcon-1024x1024"),
            title: .init(text: "Open in Nima", color: .white),
            subtitle: .init(
                text: "Choose how you’d like to continue",
                color: UIColor.white.withAlphaComponent(0.68)
            ),
            primaryButtonLabel: .init(text: "Open controlled app", color: .white),
            primaryButtonBackgroundColor: UIColor(red: 0.20, green: 0.46, blue: 0.30, alpha: 1),
            secondaryButtonLabel: .init(
                text: "Open a link",
                color: UIColor(red: 0.47, green: 0.86, blue: 0.61, alpha: 1)
            )
        )
    }
}
