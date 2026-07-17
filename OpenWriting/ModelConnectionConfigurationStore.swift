import Foundation
import Security

enum ModelConnectionConfigurationStore {
    enum StorageKey {
        static let selectedProvider = "OpenWriting.selectedProvider"
        static let modelName = "OpenWriting.modelName"
        static let apiKey = "OpenWriting.apiKey"
        static let baseURL = "OpenWriting.baseURL"
        static let customModelName = "OpenWriting.custom.modelName"
        static let customBaseURL = "OpenWriting.custom.baseURL"
        static let anthropicModelName = "OpenWriting.anthropic.modelName"
        static let anthropicBaseURL = "OpenWriting.anthropic.baseURL"
        static let clientInstallationID = "OpenWriting.clientInstallationID"
        static let didClearBundledCustomDefaults = "OpenWriting.didClearBundledCustomDefaults"
    }

    enum KeychainKey {
        static let service = "CHZ.Kral.OpenWriting.ModelConnection"
        static let openWAccount = "apiKey.openw"
        static let customAccount = "apiKey.custom"
        static let anthropicAccount = "apiKey.anthropic"
    }

    static let defaultOpenWModelName = "gpt-5.4-mini"
    static let defaultOpenWBaseURL = "https://openwriting.kralplus.asia/api/model/v1"
    static let defaultAnthropicBaseURL = "https://api.anthropic.com/v1"
    private static let previousOpenWBaseURL = "https://openwriting.kralai.tech/api/model/v1"
    private static let retiredOpenWBaseURL = "https://ai." + "xxread.top/v1"
    private static let retiredKralAPIBaseURL = "https://kralapi.kralai.tech/v1"

    static func stringValue(forKey key: String, userDefaults: UserDefaults) -> String? {
        userDefaults.string(forKey: key)
    }

    static func modelNameStorageKey(for provider: ModelProvider) -> String {
        switch provider {
        case .openAICompatible: return StorageKey.modelName
        case .custom: return StorageKey.customModelName
        case .anthropic: return StorageKey.anthropicModelName
        }
    }

    static func baseURLStorageKey(for provider: ModelProvider) -> String {
        switch provider {
        case .openAICompatible: return StorageKey.baseURL
        case .custom: return StorageKey.customBaseURL
        case .anthropic: return StorageKey.anthropicBaseURL
        }
    }

    static func keychainAccount(for provider: ModelProvider) -> String {
        switch provider {
        case .openAICompatible: return KeychainKey.openWAccount
        case .custom: return KeychainKey.customAccount
        case .anthropic: return KeychainKey.anthropicAccount
        }
    }

    static func defaultModelName(for provider: ModelProvider) -> String {
        switch provider {
        case .openAICompatible: return defaultOpenWModelName
        case .custom: return ""
        case .anthropic: return ""
        }
    }

    static func defaultBaseURL(for provider: ModelProvider) -> String {
        switch provider {
        case .openAICompatible: return defaultOpenWBaseURL
        case .custom: return ""
        case .anthropic: return defaultAnthropicBaseURL
        }
    }

    static func loadSelectedProvider(userDefaults: UserDefaults = .standard) -> ModelProvider {
        let storedProvider = ModelProvider(
            rawValue: stringValue(forKey: StorageKey.selectedProvider, userDefaults: userDefaults) ?? ""
        ) ?? .openAICompatible

        if shouldTreatCustomProviderAsServerManagedOpenWriting(userDefaults: userDefaults) {
            return .openAICompatible
        }

        return storedProvider == .anthropic ? .custom : storedProvider
    }

    static func clearBundledCustomDefaultsIfNeeded(_ userDefaults: UserDefaults) {
        guard !userDefaults.bool(forKey: StorageKey.didClearBundledCustomDefaults) else { return }

        let bundledCustomBaseURLs = [
            "https://api.openai.com/v1",
            "http://api.openai.com/v1"
        ]
        if let customBaseURL = stringValue(forKey: StorageKey.customBaseURL, userDefaults: userDefaults),
           let normalizedCustomBaseURL = normalizedBaseURLString(from: customBaseURL),
           bundledCustomBaseURLs.contains(normalizedCustomBaseURL) {
            userDefaults.removeObject(forKey: StorageKey.customBaseURL)
        }

        let bundledCustomModels = [
            "gpt-4.1-mini",
            "gpt-4o-mini",
            "gpt-5.4-mini",
            defaultOpenWModelName
        ]
        if let customModelName = stringValue(forKey: StorageKey.customModelName, userDefaults: userDefaults)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           bundledCustomModels.contains(customModelName) {
            userDefaults.removeObject(forKey: StorageKey.customModelName)
        }

        userDefaults.set(true, forKey: StorageKey.didClearBundledCustomDefaults)
    }

    static func loadModelName(for provider: ModelProvider, userDefaults: UserDefaults) -> String {
        stringValue(forKey: modelNameStorageKey(for: provider), userDefaults: userDefaults)
            ?? defaultModelName(for: provider)
    }

    static func loadBaseURL(for provider: ModelProvider, userDefaults: UserDefaults) -> String {
        let storedBaseURL = stringValue(forKey: baseURLStorageKey(for: provider), userDefaults: userDefaults)
            ?? defaultBaseURL(for: provider)
        return baseURLReplacingRetiredDefault(storedBaseURL, for: provider)
    }

    static func serverManagedAdditionalHeaders(
        accountID: String? = nil,
        userDefaults: UserDefaults = .standard
    ) -> [String: String] {
        var headers = [
            "X-OpenWriting-App-Version": appVersionHeaderValue(),
            "X-OpenWriting-Client": "macOS",
            "X-OpenWriting-Installation-ID": loadOrCreateClientInstallationID(userDefaults: userDefaults)
        ]

        if let accountHeader = sanitizedHeaderValue(accountID) {
            headers["X-OpenWriting-Account-ID"] = accountHeader
        }

        return headers
    }

    static func loadOrCreateClientInstallationID(userDefaults: UserDefaults = .standard) -> String {
        if let storedValue = sanitizedHeaderValue(
            stringValue(forKey: StorageKey.clientInstallationID, userDefaults: userDefaults)
        ),
           UUID(uuidString: storedValue) != nil {
            return storedValue
        }

        let newValue = UUID().uuidString
        userDefaults.set(newValue, forKey: StorageKey.clientInstallationID)
        return newValue
    }

    static func normalizedBaseURLString(from rawValue: String) -> String? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              var components = URLComponents(string: trimmedValue)
        else { return nil }

        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.isEmpty {
            components.path = "/v1"
        } else {
            components.path = "/" + trimmedPath
        }

        return components.url?.absoluteString
    }

    private nonisolated static func appVersionHeaderValue() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let joinedVersion = [version, build]
            .compactMap(sanitizedHeaderValue)
            .joined(separator: " ")
        return joinedVersion.isEmpty ? "unknown" : joinedVersion
    }

    private nonisolated static func sanitizedHeaderValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let sanitized = value
            .unicodeScalars
            .filter { scalar in
                !CharacterSet.controlCharacters.contains(scalar)
            }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? nil : sanitized
    }

    static func baseURLReplacingRetiredDefault(_ rawValue: String, for provider: ModelProvider) -> String {
        guard provider == .openAICompatible,
              isRetiredOpenWBaseURL(rawValue) ||
              isRetiredKralAPIBaseURL(rawValue) ||
              isPreviousOpenWBaseURL(rawValue)
        else { return rawValue }

        return defaultOpenWBaseURL
    }

    static func isRetiredOpenWBaseURL(_ rawValue: String) -> Bool {
        normalizedBaseURLString(from: rawValue) == retiredOpenWBaseURL
    }

    static func isRetiredKralAPIBaseURL(_ rawValue: String) -> Bool {
        normalizedBaseURLString(from: rawValue) == retiredKralAPIBaseURL
    }

    static func isPreviousOpenWBaseURL(_ rawValue: String) -> Bool {
        normalizedBaseURLString(from: rawValue) == previousOpenWBaseURL
    }

    static func isServerManagedOpenWritingBaseURL(_ rawValue: String) -> Bool {
        let normalizedBaseURL = normalizedBaseURLString(from: rawValue)
        return normalizedBaseURL == defaultOpenWBaseURL || normalizedBaseURL == previousOpenWBaseURL
    }

    static func shouldTreatCustomProviderAsServerManagedOpenWriting(userDefaults: UserDefaults) -> Bool {
        let storedProvider = ModelProvider(
            rawValue: stringValue(forKey: StorageKey.selectedProvider, userDefaults: userDefaults) ?? ""
        )
        guard storedProvider == .custom,
              let customBaseURL = stringValue(forKey: StorageKey.customBaseURL, userDefaults: userDefaults)
        else { return false }

        return isRetiredKralAPIBaseURL(customBaseURL) || isServerManagedOpenWritingBaseURL(customBaseURL)
    }

    static func migrateServerManagedOpenWritingProviderIfNeeded(_ userDefaults: UserDefaults) {
        guard shouldTreatCustomProviderAsServerManagedOpenWriting(userDefaults: userDefaults) else { return }

        let customModelName = stringValue(forKey: StorageKey.customModelName, userDefaults: userDefaults)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let customModelName, !customModelName.isEmpty {
            userDefaults.set(customModelName, forKey: StorageKey.modelName)
        }
        userDefaults.set(defaultOpenWBaseURL, forKey: StorageKey.baseURL)
        userDefaults.set(ModelProvider.openAICompatible.rawValue, forKey: StorageKey.selectedProvider)
    }

    static func loadAPIKeyFromKeychain(for provider: ModelProvider) -> String? {
        guard provider.requiresAPIKey else { return nil }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: KeychainKey.service,
            kSecAttrAccount: keychainAccount(for: provider),
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }

        return value
    }

    @discardableResult
    static func saveAPIKeyToKeychain(_ apiKey: String, for provider: ModelProvider) -> Bool {
        guard provider.requiresAPIKey else {
            deleteAPIKeyFromKeychain(for: provider)
            return true
        }

        let encodedValue = Data(apiKey.utf8)
        let account = keychainAccount(for: provider)
        let baseQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: KeychainKey.service,
            kSecAttrAccount: account
        ]

        let attributes: [CFString: Any] = [kSecValueData: encodedValue]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        var addQuery = baseQuery
        addQuery[kSecValueData] = encodedValue
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func deleteAPIKeyFromKeychain(for provider: ModelProvider) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: KeychainKey.service,
            kSecAttrAccount: keychainAccount(for: provider)
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func loadConnectionConfiguration(userDefaults: UserDefaults = .standard) throws -> AIConnectionConfiguration {
        let provider = loadSelectedProvider(userDefaults: userDefaults)
        let rawModelName = loadModelName(for: provider, userDefaults: userDefaults)
        let rawBaseURL = loadBaseURL(for: provider, userDefaults: userDefaults)
        let rawAPIKey = provider.requiresAPIKey ? loadAPIKeyFromKeychain(for: provider) ?? "" : ""

        let modelName = rawModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = rawAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else {
            throw ModelConnectionConfigurationError.missingModelName(provider: provider)
        }
        guard let normalizedBaseURL = normalizedBaseURLString(from: rawBaseURL),
              let baseURL = URL(string: normalizedBaseURL)
        else {
            throw ModelConnectionConfigurationError.invalidBaseURL(provider: provider, value: rawBaseURL)
        }
        guard !provider.requiresAPIKey || !apiKey.isEmpty else {
            throw ModelConnectionConfigurationError.missingAPIKey(provider: provider)
        }

        return AIConnectionConfiguration(
            baseURL: baseURL,
            apiKey: apiKey,
            modelName: modelName,
            apiFormat: provider.apiFormat,
            additionalHeaders: provider == .openAICompatible
                ? serverManagedAdditionalHeaders(userDefaults: userDefaults)
                : [:]
        )
    }
}

enum ModelConnectionConfigurationError: LocalizedError {
    case missingModelName(provider: ModelProvider)
    case invalidBaseURL(provider: ModelProvider, value: String)
    case missingAPIKey(provider: ModelProvider)

    var errorDescription: String? {
        switch self {
        case let .missingModelName(provider):
            return "\(provider.title) 模型 ID 为空，请先在 OpenWriting 设置里配置模型。"
        case let .invalidBaseURL(provider, value):
            return "\(provider.title) Base URL 无效：\(value)"
        case let .missingAPIKey(provider):
            return "\(provider.title) API Key 为空，请先在 OpenWriting 设置里保存密钥。"
        }
    }
}
