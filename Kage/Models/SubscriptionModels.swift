import Foundation

// MARK: - Subscription Status
enum SubscriptionStatus {
    case notSubscribed
    case trial
    case active
    case expired
    case cancelled
}

// MARK: - Purchase State
enum PurchaseState: Equatable {
    case idle
    case purchasing
    case restoring
    case success
    case failed(Error)
    
    static func == (lhs: PurchaseState, rhs: PurchaseState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.purchasing, .purchasing),
             (.restoring, .restoring),
             (.success, .success):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - Subscription Product
struct SubscriptionProduct {
    let identifier: String
    let title: String
    let description: String
    let price: String
    let trialPeriod: String?
}

// MARK: - Purchase Error
enum PurchaseError: LocalizedError {
    case userCancelled
    case networkError
    case purchaseNotAllowed
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Purchase was cancelled"
        case .networkError:
            return "Network connection error"
        case .purchaseNotAllowed:
            return "Purchases are not allowed on this device"
        case .unknown(let message):
            return message
        }
    }
} 