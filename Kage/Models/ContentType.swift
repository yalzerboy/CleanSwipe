import Foundation
import SwiftUI

enum ContentType: String, CaseIterable, Codable {
    case photos = "Photos"
    case videos = "Videos"
    case photosAndVideos = "Photos & Videos"
    
    var description: String {
        switch self {
        case .photos:
            return "Only photos will be shown for review"
        case .videos:
            return "Only videos will be shown for review"
        case .photosAndVideos:
            return "Both photos and videos will be shown for review"
        }
    }
    
    var icon: String {
        switch self {
        case .photos:
            return "photo"
        case .videos:
            return "video"
        case .photosAndVideos:
            return "photo.on.rectangle"
        }
    }
}

enum PhotoCount: String, CaseIterable, Identifiable {
    case few = "less_than_1000"
    case medium = "1000_5000"
    case large = "5000_10000"
    case extraLarge = "more_than_10000"
    
    var id: String { rawValue }
    
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .few: return "Less than 1,000"
        case .medium: return "1,000 - 5,000"
        case .large: return "5,000 - 10,000"
        case .extraLarge: return "More than 10,000"
        }
    }
}

enum CleaningFrequency: String, CaseIterable, Identifiable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case rarely = "rarely"
    case never = "never"
    
    var id: String { rawValue }
    
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .rarely: return "Rarely"
        case .never: return "Never"
        }
    }
}

enum StorageAvailability: String, CaseIterable, Identifiable {
    case low = "less_than_1gb"
    case medium = "1gb_5gb"
    case high = "more_than_5gb"
    case unsure = "unsure"
    
    var id: String { rawValue }
    
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .low: return "Less than 1GB"
        case .medium: return "1GB - 5GB"
        case .high: return "More than 5GB"
        case .unsure: return "Not sure"
        }
    }
}

enum ICloudStorageStatus: String, CaseIterable, Identifiable {
    case yes = "yes"
    case no = "no"
    case unsure = "unsure"
    
    var id: String { rawValue }
    
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .yes: return "Yes"
        case .no: return "No"
        case .unsure: return "Not sure"
        }
    }
}

enum StorageImpactExperience: String, CaseIterable, Identifiable {
    case often = "often"
    case sometimes = "sometimes"
    case rarely = "rarely"
    case never = "never"
    
    var id: String { rawValue }
    
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .often: return "Yes, often"
        case .sometimes: return "Occasionally"
        case .rarely: return "Rarely"
        case .never: return "No, never"
        }
    }
}

enum OnboardingStep {
    case welcome

    case benefits
    case interactiveDemo
    case age
    case photoCount

    case storageAvailability
    case iCloudStorage
    case storageImpact
    case contentType
    case preparing
    case socialProof
    case freeTrialIntro
    case permissions
    case finalContinue
}

enum WelcomeStep {
    case photoAccess
    case notifications
} 