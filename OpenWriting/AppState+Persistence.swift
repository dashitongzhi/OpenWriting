import Foundation
import Security

// MARK: - Storage Keys & Persistence

extension AppState {
    enum StorageKey {
        static let selectedProvider = ModelConnectionConfigurationStore.StorageKey.selectedProvider
        static let modelName = ModelConnectionConfigurationStore.StorageKey.modelName
        static let apiKey = ModelConnectionConfigurationStore.StorageKey.apiKey
        static let baseURL = ModelConnectionConfigurationStore.StorageKey.baseURL
        static let customModelName = ModelConnectionConfigurationStore.StorageKey.customModelName
        static let customBaseURL = ModelConnectionConfigurationStore.StorageKey.customBaseURL
        static let anthropicModelName = ModelConnectionConfigurationStore.StorageKey.anthropicModelName
        static let anthropicBaseURL = ModelConnectionConfigurationStore.StorageKey.anthropicBaseURL
        static let clientInstallationID = ModelConnectionConfigurationStore.StorageKey.clientInstallationID
        static let autoValidateOnLaunch = "OpenWriting.autoValidateOnLaunch"
        static let showWritingDeskCachePanel = "OpenWriting.showWritingDeskCachePanel"
        static let showWritingDeskTimeline = "OpenWriting.showWritingDeskTimeline"
        static let isWritingFocusModeEnabled = "OpenWriting.isWritingFocusModeEnabled"
        static let draftEditorFontSize = "OpenWriting.draftEditorFontSize"
        static let draftEditorLineSpacing = "OpenWriting.draftEditorLineSpacing"
        static let hasAcceptedAIDataTransfer = "OpenWriting.hasAcceptedAIDataTransfer"
        static let legacyActiveAccountEmail = "OpenWriting.activeAccountEmail"
        static let activeAppleUserID = "OpenWriting.activeAppleUserID"
        static let activeAppleUserEmail = "OpenWriting.activeAppleUserEmail"
        static let activeAppleUserName = "OpenWriting.activeAppleUserName"
        static let activeProjectID = "OpenWriting.activeProjectID"
        static let recentProjects = "OpenWriting.recentProjects"
        static let writingSkills = "OpenWriting.writingSkills"
        static let projectSnapshotTimestamp = "OpenWriting.projectSnapshotTimestamp"
        static let didMigrateLegacyDefaults = "OpenWriting.didMigrateLegacyDefaults"
        static let didMigrateLegacyEmailScope = "OpenWriting.didMigrateLegacyEmailScope"
    }

    // 遗留 Key 前缀采用拼接，避免编译产物中被搜索到旧品牌名
    enum LegacyStorageKey {
        private static let prefix = "Open" + "Reading"

        static let selectedProvider = "\(prefix).selectedProvider"
        static let modelName = "\(prefix).modelName"
        static let baseURL = "\(prefix).baseURL"
        static let apiKey = "\(prefix).apiKey"
        static let autoValidateOnLaunch = "\(prefix).autoValidateOnLaunch"
        static let showWritingDeskCachePanel = "\(prefix).showWritingDeskCachePanel"
        static let showWritingDeskTimeline = "\(prefix).showWritingDeskTimeline"
        static let isWritingFocusModeEnabled = "\(prefix).isWritingFocusModeEnabled"
        static let draftEditorFontSize = "\(prefix).draftEditorFontSize"
        static let draftEditorLineSpacing = "\(prefix).draftEditorLineSpacing"
        static let activeProjectID = "\(prefix).activeProjectID"
        static let recentProjects = "\(prefix).recentProjects"
    }

    enum KeychainKey {
        static let service = ModelConnectionConfigurationStore.KeychainKey.service
        static let openWAccount = ModelConnectionConfigurationStore.KeychainKey.openWAccount
        static let customAccount = ModelConnectionConfigurationStore.KeychainKey.customAccount
        static let anthropicAccount = ModelConnectionConfigurationStore.KeychainKey.anthropicAccount
    }

    static let defaultOpenWModelName = ModelConnectionConfigurationStore.defaultOpenWModelName
    static let defaultOpenWBaseURL = ModelConnectionConfigurationStore.defaultOpenWBaseURL
    static let defaultAnthropicBaseURL = ModelConnectionConfigurationStore.defaultAnthropicBaseURL

    var currentStorageScope: String? {
        activeAccount?.userID
    }
}

// MARK: - Persistence Helpers

extension AppState {
    static func stringValue(forKey key: String, userDefaults: UserDefaults) -> String? {
        ModelConnectionConfigurationStore.stringValue(forKey: key, userDefaults: userDefaults)
    }

    static func boolValue(forKey key: String, userDefaults: UserDefaults) -> Bool? {
        if let value = userDefaults.object(forKey: key) as? Bool { return value }
        return nil
    }

    static func doubleValue(forKey key: String, userDefaults: UserDefaults) -> Double? {
        if let value = userDefaults.object(forKey: key) as? Double { return value }
        if let value = userDefaults.object(forKey: key) as? NSNumber { return value.doubleValue }
        return nil
    }

    static func dataValue(forKey key: String, userDefaults: UserDefaults) -> Data? {
        userDefaults.data(forKey: key)
    }

    static func modelNameStorageKey(for provider: ModelProvider) -> String {
        ModelConnectionConfigurationStore.modelNameStorageKey(for: provider)
    }

    static func baseURLStorageKey(for provider: ModelProvider) -> String {
        ModelConnectionConfigurationStore.baseURLStorageKey(for: provider)
    }

    static func keychainAccount(for provider: ModelProvider) -> String {
        ModelConnectionConfigurationStore.keychainAccount(for: provider)
    }

    static func defaultModelName(for provider: ModelProvider) -> String {
        ModelConnectionConfigurationStore.defaultModelName(for: provider)
    }

    static func defaultBaseURL(for provider: ModelProvider) -> String {
        ModelConnectionConfigurationStore.defaultBaseURL(for: provider)
    }

    static func loadModelName(for provider: ModelProvider, userDefaults: UserDefaults) -> String {
        ModelConnectionConfigurationStore.loadModelName(for: provider, userDefaults: userDefaults)
    }

    static func loadBaseURL(for provider: ModelProvider, userDefaults: UserDefaults) -> String {
        ModelConnectionConfigurationStore.loadBaseURL(for: provider, userDefaults: userDefaults)
    }

    static func serverManagedAdditionalHeaders(
        accountID: String? = nil,
        userDefaults: UserDefaults
    ) -> [String: String] {
        ModelConnectionConfigurationStore.serverManagedAdditionalHeaders(
            accountID: accountID,
            userDefaults: userDefaults
        )
    }

    static func normalizedBaseURLString(from rawValue: String) -> String? {
        ModelConnectionConfigurationStore.normalizedBaseURLString(from: rawValue)
    }

    static func baseURLReplacingRetiredDefault(_ rawValue: String, for provider: ModelProvider) -> String {
        ModelConnectionConfigurationStore.baseURLReplacingRetiredDefault(rawValue, for: provider)
    }

    static func isRetiredOpenWBaseURL(_ rawValue: String) -> Bool {
        ModelConnectionConfigurationStore.isRetiredOpenWBaseURL(rawValue)
    }

    static func isRetiredKralAPIBaseURL(_ rawValue: String) -> Bool {
        ModelConnectionConfigurationStore.isRetiredKralAPIBaseURL(rawValue)
    }

    static func migrateServerManagedOpenWritingProviderIfNeeded(_ userDefaults: UserDefaults) {
        ModelConnectionConfigurationStore.migrateServerManagedOpenWritingProviderIfNeeded(userDefaults)
    }

    static func validationFailureMessage(for error: Error, provider: ModelProvider) -> String {
        let resolvedMessage = (error as NSError).localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if provider == .openAICompatible {
            if resolvedMessage.isEmpty {
                return "OpenWriting 连接校验失败，请稍后重试或检查网络。"
            }
            return "OpenWriting 连接校验失败：\(resolvedMessage)"
        }
        if resolvedMessage.isEmpty {
            return "连接校验失败，请检查 Base URL、模型 ID 和 API Key。"
        }
        return "连接校验失败：\(resolvedMessage)"
    }
}

// MARK: - Keychain

extension AppState {
    static func loadAPIKeyFromKeychain(for provider: ModelProvider) -> String? {
        ModelConnectionConfigurationStore.loadAPIKeyFromKeychain(for: provider)
    }

    @discardableResult
    static func saveAPIKeyToKeychain(_ apiKey: String, for provider: ModelProvider) -> Bool {
        ModelConnectionConfigurationStore.saveAPIKeyToKeychain(apiKey, for: provider)
    }

    static func deleteAPIKeyFromKeychain(for provider: ModelProvider) {
        ModelConnectionConfigurationStore.deleteAPIKeyFromKeychain(for: provider)
    }
}

// MARK: - Instance Persistence

extension AppState {
    func persistSelectedProvider() {
        userDefaults.set(selectedProvider.rawValue, forKey: StorageKey.selectedProvider)
    }

    func persistModelName() {
        userDefaults.set(modelName, forKey: Self.modelNameStorageKey(for: selectedProvider))
    }

    func persistBaseURL() {
        userDefaults.set(baseURL, forKey: Self.baseURLStorageKey(for: selectedProvider))
    }

    func persistConnectionSettings(for provider: ModelProvider) {
        userDefaults.set(modelName, forKey: Self.modelNameStorageKey(for: provider))
        userDefaults.set(baseURL, forKey: Self.baseURLStorageKey(for: provider))

        guard provider.requiresAPIKey else {
            Self.deleteAPIKeyFromKeychain(for: provider)
            return
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            Self.deleteAPIKeyFromKeychain(for: provider)
        } else {
            Self.saveAPIKeyToKeychain(trimmedKey, for: provider)
        }
    }

    func loadConnectionSettings(for provider: ModelProvider) {
        isApplyingProviderConfiguration = true
        modelName = Self.loadModelName(for: provider, userDefaults: userDefaults)
        baseURL = Self.loadBaseURL(for: provider, userDefaults: userDefaults)
        apiKey = provider.requiresAPIKey ? Self.loadAPIKeyFromKeychain(for: provider) ?? "" : ""
        isApplyingProviderConfiguration = false
        refreshIdleValidationMessage()
    }

    func persistAutoValidatePreference() {
        userDefaults.set(autoValidateOnLaunch, forKey: StorageKey.autoValidateOnLaunch)
    }

    func persistWritingDeskDisplayPreferences() {
        userDefaults.set(showWritingDeskCachePanel, forKey: StorageKey.showWritingDeskCachePanel)
        userDefaults.set(showWritingDeskTimeline, forKey: StorageKey.showWritingDeskTimeline)
        userDefaults.set(isWritingFocusModeEnabled, forKey: StorageKey.isWritingFocusModeEnabled)
        userDefaults.set(draftEditorFontSize, forKey: StorageKey.draftEditorFontSize)
        userDefaults.set(draftEditorLineSpacing, forKey: StorageKey.draftEditorLineSpacing)
    }

    func persistActiveProjectID() {
        let key = Self.activeProjectIDStorageKey(for: currentStorageScope)
        if let activeProjectID {
            userDefaults.set(activeProjectID, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    @discardableResult
    func persistRecentProjects(_ projects: [NovelProject], for scope: String?) -> Bool {
        guard isCurrentStoragePersistenceSafe, scope == currentStorageScope else {
            setCloudSyncStatus(
                title: "本机存储待恢复",
                symbolName: "exclamationmark.triangle",
                message: "检测到本机项目文件不完整，已停止自动保存和同步；请先在项目空间导出诊断或执行恢复。"
            )
            return false
        }
        do {
            try projectStore.saveProjects(projects, for: scope)
            Self.clearLegacyRecentProjectsFromUserDefaults(for: scope, userDefaults: userDefaults)
            return true
        } catch {
            setCloudSyncStatus(
                title: "保存失败",
                symbolName: "exclamationmark.triangle",
                message: error.localizedDescription
            )
            return false
        }
    }

    func scheduleRecentProjectsPersistence(snapshot: [NovelProject], for scope: String?) {
        let storageKey = Self.recentProjectsStorageKey(for: scope)
        recentProjectsPersistTasks[storageKey]?.cancel()
        recentProjectsPersistTasks[storageKey] = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            guard self.isCurrentStoragePersistenceSafe, scope == self.currentStorageScope else { return }
            self.persistRecentProjects(snapshot, for: scope)
            recentProjectsPersistTasks.removeValue(forKey: storageKey)
        }
    }

    func persistAPIKey() {
        guard selectedProvider.requiresAPIKey else {
            Self.deleteAPIKeyFromKeychain(for: selectedProvider)
            return
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            Self.deleteAPIKeyFromKeychain(for: selectedProvider)
            return
        }
        Self.saveAPIKeyToKeychain(trimmedKey, for: selectedProvider)
    }

    func persistActiveAccountProfile() {
        if let activeAccount {
            userDefaults.set(activeAccount.userID, forKey: StorageKey.activeAppleUserID)
            if activeAccount.email.isEmpty {
                userDefaults.removeObject(forKey: StorageKey.activeAppleUserEmail)
            } else {
                userDefaults.set(activeAccount.email, forKey: StorageKey.activeAppleUserEmail)
            }
            if activeAccount.fullName.isEmpty {
                userDefaults.removeObject(forKey: StorageKey.activeAppleUserName)
            } else {
                userDefaults.set(activeAccount.fullName, forKey: StorageKey.activeAppleUserName)
            }
        } else {
            userDefaults.removeObject(forKey: StorageKey.activeAppleUserID)
            userDefaults.removeObject(forKey: StorageKey.activeAppleUserEmail)
            userDefaults.removeObject(forKey: StorageKey.activeAppleUserName)
        }
    }

    func persistProjectSnapshotTimestamp() {
        let key = Self.projectSnapshotTimestampStorageKey(for: currentStorageScope)
        if currentProjectSnapshotTimestamp > 0 {
            userDefaults.set(currentProjectSnapshotTimestamp, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Migration

extension AppState {
    static func migrateLegacyUserDefaultsIfNeeded(
        _ userDefaults: UserDefaults,
        projectStore: ProjectFileStore
    ) {
        guard !userDefaults.bool(forKey: StorageKey.didMigrateLegacyDefaults) else { return }

        copyStringValue(from: LegacyStorageKey.selectedProvider, to: StorageKey.selectedProvider, userDefaults: userDefaults)
        copyStringValue(from: LegacyStorageKey.modelName, to: StorageKey.modelName, userDefaults: userDefaults)
        copyStringValue(from: LegacyStorageKey.baseURL, to: StorageKey.baseURL, userDefaults: userDefaults)
        copyBoolValue(from: LegacyStorageKey.autoValidateOnLaunch, to: StorageKey.autoValidateOnLaunch, userDefaults: userDefaults)
        copyBoolValue(from: LegacyStorageKey.showWritingDeskCachePanel, to: StorageKey.showWritingDeskCachePanel, userDefaults: userDefaults)
        copyBoolValue(from: LegacyStorageKey.showWritingDeskTimeline, to: StorageKey.showWritingDeskTimeline, userDefaults: userDefaults)
        copyBoolValue(from: LegacyStorageKey.isWritingFocusModeEnabled, to: StorageKey.isWritingFocusModeEnabled, userDefaults: userDefaults)
        copyDoubleValue(from: LegacyStorageKey.draftEditorFontSize, to: StorageKey.draftEditorFontSize, userDefaults: userDefaults)
        copyDoubleValue(from: LegacyStorageKey.draftEditorLineSpacing, to: StorageKey.draftEditorLineSpacing, userDefaults: userDefaults)
        copyStringValue(from: LegacyStorageKey.activeProjectID, to: StorageKey.activeProjectID, userDefaults: userDefaults)

        if !projectStore.hasProjects(for: nil),
           let legacyProjectsData = userDefaults.data(forKey: LegacyStorageKey.recentProjects),
           let legacyProjects = Self.decodeProjects(from: legacyProjectsData),
           (try? projectStore.saveProjects(legacyProjects, for: nil)) != nil {
            userDefaults.removeObject(forKey: LegacyStorageKey.recentProjects)
        }

        // API Key intentionally stays out of automatic legacy migration so app launch never
        // touches old keychain entries or triggers repeated password prompts.
        userDefaults.set(true, forKey: StorageKey.didMigrateLegacyDefaults)
    }

    static func migrateRetiredOpenAICompatibleDefaults(_ userDefaults: UserDefaults) {
        replaceRetiredOpenWBaseURLIfNeeded(forKey: StorageKey.baseURL, userDefaults: userDefaults)
        replaceRetiredOpenWBaseURLIfNeeded(forKey: LegacyStorageKey.baseURL, userDefaults: userDefaults)
        migrateServerManagedOpenWritingProviderIfNeeded(userDefaults)
    }

    private static func replaceRetiredOpenWBaseURLIfNeeded(forKey key: String, userDefaults: UserDefaults) {
        guard let storedBaseURL = stringValue(forKey: key, userDefaults: userDefaults),
              isRetiredOpenWBaseURL(storedBaseURL) || isRetiredKralAPIBaseURL(storedBaseURL)
        else { return }

        userDefaults.set(defaultOpenWBaseURL, forKey: key)
    }

    static func migrateAPIKeysToKeychainIfNeeded(_ userDefaults: UserDefaults) {
        deleteAPIKeyFromKeychain(for: .openAICompatible)
        userDefaults.removeObject(forKey: StorageKey.apiKey)
        userDefaults.removeObject(forKey: LegacyStorageKey.apiKey)
    }

    static func migrateLegacyEmailScopeIfNeeded(
        _ userDefaults: UserDefaults,
        projectStore: ProjectFileStore
    ) {
        guard !userDefaults.bool(forKey: StorageKey.didMigrateLegacyEmailScope) else { return }
        defer { userDefaults.set(true, forKey: StorageKey.didMigrateLegacyEmailScope) }

        guard let legacyEmail = stringValue(forKey: StorageKey.legacyActiveAccountEmail, userDefaults: userDefaults)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !legacyEmail.isEmpty
        else { return }

        copyAccountScopedProjectData(
            from: legacyEmail,
            to: nil,
            userDefaults: userDefaults,
            projectStore: projectStore
        )
        userDefaults.removeObject(forKey: StorageKey.legacyActiveAccountEmail)
    }

    static func copyAccountScopedProjectData(
        from sourceScope: String?,
        to targetScope: String?,
        userDefaults: UserDefaults,
        projectStore: ProjectFileStore
    ) {
        if !projectStore.hasProjects(for: targetScope),
           let recentProjects = Self.loadRecentProjects(
                for: sourceScope,
                from: userDefaults,
                projectStore: projectStore
           ) {
            try? projectStore.saveProjects(recentProjects, for: targetScope)
        }

        let sourceActiveProjectKey = activeProjectIDStorageKey(for: sourceScope)
        let targetActiveProjectKey = activeProjectIDStorageKey(for: targetScope)
        if userDefaults.string(forKey: targetActiveProjectKey) == nil,
           let activeProjectID = userDefaults.string(forKey: sourceActiveProjectKey) {
            userDefaults.set(activeProjectID, forKey: targetActiveProjectKey)
        }

        let sourceTimestampKey = projectSnapshotTimestampStorageKey(for: sourceScope)
        let targetTimestampKey = projectSnapshotTimestampStorageKey(for: targetScope)
        if userDefaults.object(forKey: targetTimestampKey) == nil,
           let timestamp = userDefaults.object(forKey: sourceTimestampKey) {
            userDefaults.set(timestamp, forKey: targetTimestampKey)
        }
    }

    static func copyStringValue(from legacyKey: String, to currentKey: String, userDefaults: UserDefaults) {
        guard userDefaults.string(forKey: currentKey) == nil,
              let value = userDefaults.string(forKey: legacyKey) else { return }
        userDefaults.set(value, forKey: currentKey)
    }

    static func copyBoolValue(from legacyKey: String, to currentKey: String, userDefaults: UserDefaults) {
        guard userDefaults.object(forKey: currentKey) == nil,
              let value = userDefaults.object(forKey: legacyKey) as? Bool else { return }
        userDefaults.set(value, forKey: currentKey)
    }

    static func copyDoubleValue(from legacyKey: String, to currentKey: String, userDefaults: UserDefaults) {
        guard userDefaults.object(forKey: currentKey) == nil,
              let value = doubleValue(forKey: legacyKey, userDefaults: userDefaults) else { return }
        userDefaults.set(value, forKey: currentKey)
    }
}

// MARK: - Template Defaults

extension AppState {
    static func defaultProjectSummary(for length: NovelLength) -> String {
        switch length {
        case .short:
            return "围绕一个核心冲突或情绪爆点，完成一次清晰、集中、可回收的短篇叙事闭环。"
        case .medium:
            return "以一条主线带动少量副线，在有限篇幅内完成角色变化、冲突升级与阶段回收。"
        case .long:
            return "从一句 logline 起步，逐步补齐分卷目标、长期冲突、角色弧线与伏笔回收，支撑连续长篇创作。"
        }
    }

    static func defaultChapterFocus(for length: NovelLength) -> String {
        switch length {
        case .short:
            return "尽快写出开场钩子、核心冲突和会在结尾回收的关键决定。"
        case .medium:
            return "先立稳主角目标、当前阶段阻力和第一轮关系变化，再推进本章转折。"
        case .long:
            return "先写出开篇场景的情绪、主角目标和第一个冲突钩子，并给长期主线留出延展空间。"
        }
    }

    static func defaultWordTargetText(for length: NovelLength) -> String {
        switch length {
        case .short:
            return "全文建议 6000-15000 字；单次生成建议 700-1000 字；尽量在 1-3 个关键场景内完成闭环。"
        case .medium:
            return "全文建议 30000-120000 字；按 8-20 章推进；单章建议 1600-2400 字。"
        case .long:
            return "全文建议 300000 字以上；按分卷/阶段推进；单章建议 1800-2600 字，关键节点可适当上浮。"
        }
    }

    static func defaultContinuityNotes(for length: NovelLength) -> String {
        switch length {
        case .short:
            return "优先维持单一视角、情绪线和结尾闭环，避免引入过多未来才回收的信息。"
        case .medium:
            return "优先维持主线推进、主要关系线变化和阶段回收节奏，不要让中段散掉。"
        case .long:
            return "先把主角动机、长期冲突来源、章节语气和世界规则稳定下来，再逐步扩展分卷目标与长期伏笔。"
        }
    }

    static func defaultSpecialRequirements(for length: NovelLength) -> String {
        switch length {
        case .short:
            return "优先保证冲突集中、信息有效、结尾回收，不要把故事拖成散文式铺陈。"
        case .medium:
            return "控制支线数量，确保每章都服务于主线推进、关系变化或关键伏笔。"
        case .long:
            return "不要一次性说透长期线索，保持阶段推进、持续悬念和卷末回收节奏。"
        }
    }

    static func defaultStructureNotes(for length: NovelLength) -> String {
        switch length {
        case .short:
            return """
            1. 开场快速建立主角处境与核心冲突
            2. 中段持续加压，逼出选择或代价
            3. 结尾完成事件或情绪闭环
            """
        case .medium:
            return """
            1. 前段建立主角目标、阻力和主要关系
            2. 中段升级冲突并制造一次明显反转
            3. 尾段完成阶段回收，并为最终落点蓄力
            """
        case .long:
            return """
            1. 第一卷负责开篇钩子、主角目标与世界规则落地
            2. 中期分卷持续升级敌我关系、代价与伏笔
            3. 大后期集中回收长期伏笔并推动终局决战
            """
        }
    }

    static func defaultSceneProgressNotes(for length: NovelLength) -> String {
        switch length {
        case .short:
            return """
            1. 第一场直接落冲突或异常
            2. 第二场把问题逼到不可回避
            3. 最后一场完成揭示、决定或代价
            """
        case .medium:
            return """
            1. 开场先交代本阶段目标和当下阻力
            2. 中段安排一次推进失败或关系变形
            3. 结尾留下能驱动下一章的结果或新问题
            """
        case .long:
            return """
            1. 开场先落当前章目标、风险和人物态度
            2. 中段推进线索、关系或局势，并制造信息增量
            3. 结尾抛出下一章必须追的缺口，不提前透支真相
            """
        }
    }

    static func defaultCharacterArcNotes(for length: NovelLength) -> String {
        switch length {
        case .short:
            return """
            主角：在一次关键选择中完成情绪或认知转变
            对手/陪衬人物：负责施压、映照或引发主角变化
            """
        case .medium:
            return """
            主角：从当前缺口出发，完成一轮明显的阶段成长
            核心配角：推动关系变化或揭示主角盲点
            对抗方：持续施压，但不要抢走主线焦点
            """
        case .long:
            return """
            主角：拆成阶段成长，不要一卷走完整条弧线
            核心配角：分别承担关系线、功能线和价值观碰撞
            长期对抗方：持续制造压力和误导，逐步显露真面目
            """
        }
    }

    static func defaultForeshadowNotes(for length: NovelLength) -> String {
        switch length {
        case .short:
            return """
            1. 只保留必须在文末回收的关键伏笔
            2. 伏笔最好与主角决定或结尾反转直接相关
            """
        case .medium:
            return """
            1. 保留主线伏笔和 1-2 条关系线伏笔
            2. 明确哪些要在中段回收，哪些留到结尾
            """
        case .long:
            return """
            1. 区分本卷伏笔、跨卷伏笔和长期误导信息
            2. 记录每条伏笔第一次出现、下一次推进和最终回收节点
            """
        }
    }

    static func defaultVolumePlanNotes(for length: NovelLength) -> String {
        switch length {
        case .short: return ""
        case .medium:
            return """
            阶段一：建立主线目标、主要阻力和人物关系底色
            阶段二：加压、反转并逼出新的选择
            阶段三：回收主线冲突，完成角色变化
            """
        case .long:
            return """
            第一卷：开篇钩子、主角目标、世界规则、卷末第一次反转
            第二卷：扩大冲突范围，推进敌我关系和长期伏笔
            第三卷及以后：按阶段升级代价与真相，逐步回收长期线索
            """
        }
    }

    static func defaultActiveThreadsNotes(for length: NovelLength) -> String {
        switch length {
        case .short: return ""
        case .medium:
            return """
            主线：当前阶段最重要的目标与阻力
            关系线：本阶段最需要推进或制造变化的关系
            伏笔线：本阶段必须继续提一次的关键埋点
            """
        case .long:
            return """
            主线：当前卷最重要的推进目标与阻力
            支线：此刻仍在进行、且不能失踪的角色线/任务线
            伏笔线：下一次必须露面的长期埋点与误导信息
            回收线：最近 3 章内需要兑现、解释或翻面的旧伏笔
            """
        }
    }

    static func defaultOutlineGenerationProfile(for length: NovelLength) -> OutlineGenerationProfile {
        switch length {
        case .short:
            return OutlineGenerationProfile(
                storyFlow: "围绕一次核心事件，完成起因、升级、决定和结尾回收。",
                worldDescription: "只保留支撑本次冲突的必要背景和规则。",
                protagonistTraits: "性格鲜明、动机明确、能在短时间内做出关键决定。",
                expectedLength: "全文约 0.6 万到 1.5 万字",
                endingPreference: "收束明确、情绪或事件完成闭环",
                sellingPoints: "冲突集中、结尾有效回收",
                keyEvents: "",
                storyPacing: "短促、聚焦、尽快进入正题",
                motivations: "",
                relationshipMap: "",
                antagonistPortrait: "",
                foreshadowingNotes: ""
            )
        case .medium:
            return OutlineGenerationProfile(
                storyFlow: "按起始、升级、反转、收束四段推进主线，并保留少量副线。",
                worldDescription: "把主线相关的背景、规则和对抗面说明白，但不要铺得过宽。",
                protagonistTraits: "主角有明确欲望、阶段成长空间和能推动剧情的主动性。",
                expectedLength: "全文约 3 万到 12 万字",
                endingPreference: "主线完成阶段闭环，人物获得清晰变化",
                sellingPoints: "主线集中、关系推进明显、阶段回收清楚",
                keyEvents: "",
                storyPacing: "稳步推进，中段需要明显升级或反转",
                motivations: "",
                relationshipMap: "",
                antagonistPortrait: "",
                foreshadowingNotes: ""
            )
        case .long:
            return OutlineGenerationProfile(
                storyFlow: "按分卷/阶段推进主线，每卷都要有独立目标、升级和卷末回收点。",
                worldDescription: "把长期主线需要用到的背景、规则、势力和限制说明清楚。",
                protagonistTraits: "主角具备长期成长空间、阶段欲望变化和可持续的行动驱动力。",
                expectedLength: "全文约 30 万字以上，按分卷连载推进",
                endingPreference: "终局收束明确，长期伏笔能分阶段回收",
                sellingPoints: "分卷推进、长期伏笔、角色弧线和世界状态持续演化",
                keyEvents: "",
                storyPacing: "长线连载节奏，卷内有高潮，卷末有明显翻面或升级",
                motivations: "",
                relationshipMap: "",
                antagonistPortrait: "",
                foreshadowingNotes: ""
            )
        }
    }
}
