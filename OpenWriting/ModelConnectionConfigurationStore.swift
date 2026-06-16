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
    }

    enum KeychainKey {
        static let service = "CHZ.Kral.OpenWriting.ModelConnection"
        static let openWAccount = "apiKey.openw"
        static let customAccount = "apiKey.custom"
    }

    static let defaultOpenWModelName = "gpt-5.4-mini"
    static let defaultOpenWBaseURL = "https://kralapi.kralai.tech/v1"
    private static let retiredOpenWBaseURL = "https://ai." + "xxread.top/v1"

    static func stringValue(forKey key: String, userDefaults: UserDefaults) -> String? {
        userDefaults.string(forKey: key)
    }

    static func modelNameStorageKey(for provider: ModelProvider) -> String {
        switch provider {
        case .openAICompatible: return StorageKey.modelName
        case .custom: return StorageKey.customModelName
        }
    }

    static func baseURLStorageKey(for provider: ModelProvider) -> String {
        switch provider {
        case .openAICompatible: return StorageKey.baseURL
        case .custom: return StorageKey.customBaseURL
        }
    }

    static func keychainAccount(for provider: ModelProvider) -> String {
        switch provider {
        case .openAICompatible: return KeychainKey.openWAccount
        case .custom: return KeychainKey.customAccount
        }
    }

    static func defaultModelName(for provider: ModelProvider) -> String {
        switch provider {
        case .openAICompatible: return defaultOpenWModelName
        case .custom: return ""
        }
    }

    static func defaultBaseURL(for provider: ModelProvider) -> String {
        switch provider {
        case .openAICompatible: return defaultOpenWBaseURL
        case .custom: return ""
        }
    }

    static func loadSelectedProvider(userDefaults: UserDefaults = .standard) -> ModelProvider {
        ModelProvider(
            rawValue: stringValue(forKey: StorageKey.selectedProvider, userDefaults: userDefaults) ?? ""
        ) ?? .openAICompatible
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

    static func baseURLReplacingRetiredDefault(_ rawValue: String, for provider: ModelProvider) -> String {
        guard provider == .openAICompatible,
              isRetiredOpenWBaseURL(rawValue)
        else { return rawValue }

        return defaultOpenWBaseURL
    }

    static func isRetiredOpenWBaseURL(_ rawValue: String) -> Bool {
        normalizedBaseURLString(from: rawValue) == retiredOpenWBaseURL
    }

    static func loadAPIKeyFromKeychain(for provider: ModelProvider) -> String? {
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
        let rawAPIKey = loadAPIKeyFromKeychain(for: provider) ?? ""

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
        guard !apiKey.isEmpty else {
            throw ModelConnectionConfigurationError.missingAPIKey(provider: provider)
        }

        return AIConnectionConfiguration(
            baseURL: baseURL,
            apiKey: apiKey,
            modelName: modelName
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
