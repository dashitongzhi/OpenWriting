import Foundation

nonisolated enum CommerceEntitlementTier: String, CaseIterable, Codable, Identifiable, Sendable {
    case free
    case authorPro

    var id: Self { self }

    var isPaidTier: Bool {
        self != .free
    }
}

nonisolated enum CommerceEntitlementStatus: String, Codable, Sendable {
    case notConfigured
    case active
    case inGracePeriod
    case expired
    case revoked
    case pending

    var grantsAccess: Bool {
        switch self {
        case .active, .inGracePeriod:
            return true
        case .notConfigured, .expired, .revoked, .pending:
            return false
        }
    }
}

nonisolated enum CommerceEntitlementSource: String, Codable, Sendable {
    case localDefault
    case appleAppStore
}

nonisolated struct CommerceEntitlementSnapshot: Codable, Equatable, Sendable {
    var tier: CommerceEntitlementTier
    var status: CommerceEntitlementStatus
    var source: CommerceEntitlementSource
    var productID: String?
    var expirationDate: Date?
    var updatedAt: Date

    var grantsPaidAccess: Bool {
        tier.isPaidTier && status.grantsAccess
    }

    static func localDefault(updatedAt: Date = Date()) -> CommerceEntitlementSnapshot {
        CommerceEntitlementSnapshot(
            tier: .free,
            status: .notConfigured,
            source: .localDefault,
            productID: nil,
            expirationDate: nil,
            updatedAt: updatedAt
        )
    }
}

nonisolated enum CommerceProductKind: String, Codable, Sendable {
    case nonConsumable
    case autoRenewableSubscription
}

nonisolated struct CommerceProductDescriptor: Codable, Equatable, Identifiable, Sendable {
    var productID: String
    var tier: CommerceEntitlementTier
    var kind: CommerceProductKind

    var id: String { productID }
}

nonisolated struct CommercePurchaseRequest: Equatable, Sendable {
    var productID: String
    var expectedTier: CommerceEntitlementTier
}

nonisolated enum CommercePurchaseOutcome: Equatable, Sendable {
    case completed(CommerceEntitlementSnapshot)
    case pending
    case cancelled
    case unavailable(reason: String)
    case failed(message: String)
}

nonisolated protocol CommerceEntitlementProviding: Sendable {
    func currentEntitlements(accountID: String?) async -> CommerceEntitlementSnapshot
    func purchase(_ request: CommercePurchaseRequest, accountID: String?) async -> CommercePurchaseOutcome
    func restorePurchases(accountID: String?) async -> CommerceEntitlementSnapshot
}

nonisolated struct DeferredAppleCommerceProvider: CommerceEntitlementProviding {
    static let unavailableReason = "Apple commerce integration is deferred."

    private let currentDate: @Sendable () -> Date

    init(currentDate: @escaping @Sendable () -> Date = { Date() }) {
        self.currentDate = currentDate
    }

    func currentEntitlements(accountID: String?) async -> CommerceEntitlementSnapshot {
        CommerceEntitlementSnapshot.localDefault(updatedAt: currentDate())
    }

    func purchase(_ request: CommercePurchaseRequest, accountID: String?) async -> CommercePurchaseOutcome {
        .unavailable(reason: Self.unavailableReason)
    }

    func restorePurchases(accountID: String?) async -> CommerceEntitlementSnapshot {
        CommerceEntitlementSnapshot.localDefault(updatedAt: currentDate())
    }
}

nonisolated enum AppleCommerceProductCatalog {
    static let reservedProducts: [CommerceProductDescriptor] = []
    static let storeKitIntegrationIsDeferred = true
}
