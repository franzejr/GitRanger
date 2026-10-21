import Foundation

@MainActor
@Observable
final class AISettingsViewModel {
    var providerStatuses: [(
        provider: AIProvider,
        status: AIAvailabilityStatus
    )] = []
    var isChecking = false
    var modelOptions: [AIProvider: [AIModelOption]] = [:]
    var loadingModels: Set<AIProvider> = []
    var modelLoadErrors: [AIProvider: String] = [:]

    func checkAvailability() async {
        isChecking = true
        let settings = AIServiceFactory.settingsFromUserDefaults()
        let results = await withTaskGroup(
            of: (AIProvider, AIAvailabilityStatus).self,
            returning: [(AIProvider, AIAvailabilityStatus)].self
        ) { group in
            for provider in AIProvider.allCases {
                group.addTask {
                    let service = AIServiceFactory.create(
                        provider: provider,
                        settings: settings
                    )
                    return (provider, await service.availabilityStatus())
                }
            }
            var statuses: [(AIProvider, AIAvailabilityStatus)] = []
            for await status in group { statuses.append(status) }
            return statuses
        }
        providerStatuses = results
        isChecking = false
    }

    func loadModels(for provider: AIProvider, force: Bool = false) async {
        if !force, modelOptions[provider] != nil { return }
        loadingModels.insert(provider)
        modelLoadErrors.removeValue(forKey: provider)
        let builtIn = AIModelCatalog.builtInOptions(for: provider)
        modelOptions[provider] = builtIn

        do {
            let discovered = try await AIModelDiscoveryService.shared.discover(
                provider: provider,
                settings: AIServiceFactory.settingsFromUserDefaults()
            )
            if provider == .claudeCode || provider == .codexCLI {
                let defaultOption = builtIn.filter { $0.id.isEmpty }
                let aliases = builtIn.filter { !$0.id.isEmpty }
                modelOptions[provider] = Self.merge(
                    defaultOption + discovered,
                    aliases
                )
            } else {
                modelOptions[provider] = Self.merge(builtIn, discovered)
            }
        } catch {
            modelLoadErrors[provider] = error.localizedDescription
        }
        loadingModels.remove(provider)
    }

    func models(for provider: AIProvider) -> [AIModelOption] {
        modelOptions[provider] ?? AIModelCatalog.builtInOptions(for: provider)
    }

    func isAvailable(_ provider: AIProvider) -> Bool? {
        availabilityStatus(for: provider)?.isAvailable
    }

    func availabilityStatus(
        for provider: AIProvider
    ) -> AIAvailabilityStatus? {
        providerStatuses.first { $0.provider == provider }?.status
    }

    private static func merge(
        _ primary: [AIModelOption],
        _ secondary: [AIModelOption]
    ) -> [AIModelOption] {
        var seen: Set<String> = []
        return (primary + secondary).filter { seen.insert($0.id).inserted }
    }
}
