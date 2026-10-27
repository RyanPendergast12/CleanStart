import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Customises the screen iOS shows when a shielded app or website is opened.
/// The blocked item's name is intentionally never shown.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    private func makeConfiguration() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            backgroundColor: UIColor.systemBackground,
            icon: UIImage(systemName: "leaf.circle.fill"),
            title: ShieldConfiguration.Label(text: "Paused by CleanStart", color: .label),
            subtitle: ShieldConfiguration.Label(
                text: "You chose to keep this out of your day. Take a breath — what do you actually want right now?",
                color: .secondaryLabel
            ),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: .white),
            primaryButtonBackgroundColor: UIColor.systemTeal,
            secondaryButtonLabel: nil
        )
    }
}
