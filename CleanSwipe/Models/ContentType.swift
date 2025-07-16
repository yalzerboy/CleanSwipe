import Foundation

enum ContentType: String, CaseIterable {
    case photos = "Photos"
    case photosAndVideos = "Photos & Videos"
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
    case trialDetails
    case finalContinue
}

enum WelcomeStep {
    case photoAccess
    case notifications
} 