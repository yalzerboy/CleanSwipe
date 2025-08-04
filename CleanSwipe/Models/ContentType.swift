import Foundation

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

enum PhotoCount: String, CaseIterable {
    case less500 = "Less than 500"
    case count500to1000 = "500-1000"
    case count1000to5000 = "1000-5000"
    case count5000plus = "5000+"
}

enum CleaningFrequency: String, CaseIterable {
    case daily = "Every day"
    case weekly = "Every week"
    case monthly = "Once a month"
    case fewTimes = "A few times a year"
    case never = "Never"
}

enum OnboardingStep {
    case welcome
    case howTo
    case benefits
    case age
    case photoCount
    case cleaningFrequency
    case contentType
    case preparing
    case freeTrialIntro
    case finalContinue
}

enum WelcomeStep {
    case photoAccess
    case notifications
} 