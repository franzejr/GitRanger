import Foundation

@Observable
final class AISettingsViewModel {
    var providerStatuses: [(provider: AIProvider, available: Bool)] = []
    var isChecking = false

    func checkAvailability() async {
        isChecking = true
        var results: [(AIProvider, Bool)] = []

        let settings = AIServiceFactory.settingsFromUserDefaults()

        for provider in AIProvider.allCases {
            let service = AIServiceFactory.create(provider: provider, settings: settings)
            let available = await service.isAvailable()
            results.append((provider, available))
        }

        providerStatuses = results
        isChecking = false
    }

    func isAvailable(_ provider: AIProvider) -> Bool? {
        providerStatuses.first { $0.provider == provider }?.available
    }
}
