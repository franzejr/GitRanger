import Foundation

@Observable
final class AISettingsViewModel {
    var providerStatuses: [(
        provider: AIProvider,
        status: AIAvailabilityStatus
    )] = []
    var isChecking = false

    func checkAvailability() async {
        isChecking = true
        var results: [(AIProvider, AIAvailabilityStatus)] = []

        let settings = AIServiceFactory.settingsFromUserDefaults()

        for provider in AIProvider.allCases {
            let service = AIServiceFactory.create(provider: provider, settings: settings)
            let status = await service.availabilityStatus()
            results.append((provider, status))
        }

        providerStatuses = results
        isChecking = false
    }

    func isAvailable(_ provider: AIProvider) -> Bool? {
        availabilityStatus(for: provider)?.isAvailable
    }

    func availabilityStatus(
        for provider: AIProvider
    ) -> AIAvailabilityStatus? {
        providerStatuses.first { $0.provider == provider }?.status
    }
}
