import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration()
    }

    private func makeConfiguration() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.035, green: 0.047, blue: 0.039, alpha: 0.96),
            icon: UIImage(named: "AppIcon-1024x1024"),
            title: .init(text: "Open Instagram in Nima", color: .white),
            subtitle: .init(
                text: "Choose how you’d like to continue",
                color: UIColor.white.withAlphaComponent(0.68)
            ),
            primaryButtonLabel: .init(text: "Open a link", color: .white),
            primaryButtonBackgroundColor: UIColor(red: 0.20, green: 0.46, blue: 0.30, alpha: 1),
            secondaryButtonLabel: .init(
                text: "Open in Nima",
                color: UIColor(red: 0.47, green: 0.86, blue: 0.61, alpha: 1)
            )
        )
    }
}
