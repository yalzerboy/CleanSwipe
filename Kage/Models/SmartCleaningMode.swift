import Foundation
import Photos

/// Model representing a smart cleaning mode with its detection results
struct SmartCleaningMode: Identifiable {
    let id: CleaningModeType
    let title: String
    let subtitle: String
    let icon: String
    let color: String // Color name for SwiftUI
    var assets: [PHAsset]
    var totalSize: Int64 // Size in bytes
    var isLoading: Bool
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var assetCount: Int {
        assets.count
    }
}

/// Category grouping for Smart Cleanup Hub
enum CleaningCategory: String, CaseIterable {
    case quickWins = "quick_wins"
    case deepClean = "deep_clean"
    
    var title: String {
        switch self {
        case .quickWins:
            return "Quick Wins"
        case .deepClean:
            return "Deep Clean"
        }
    }
    
    var subtitle: String {
        switch self {
        case .quickWins:
            return "Fast storage gains"
        case .deepClean:
            return "Thorough cleanup"
        }
    }
}

/// Types of smart cleaning modes available
enum CleaningModeType: String, CaseIterable, Identifiable {
    case largeMedia = "large_media"
    case documents = "documents"
    case screenRecordings = "screen_recordings"
    case similarPhotos = "similar_photos"
    case blurryPhotos = "blurry_photos"
    case oldScreenshots = "old_screenshots"
    case largeVideos = "large_videos"
    case livePhotos = "live_photos"
    case savedImages = "saved_images"
    case burstPhotos = "burst_photos"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .largeMedia:
            return "Large Media"
        case .documents:
            return "Notes & Docs"
        case .screenRecordings:
            return "Screen Recordings"
        case .similarPhotos:
            return "Similar Photos"
        case .blurryPhotos:
            return "Blurry & Dark"
        case .oldScreenshots:
            return "Old Screenshots"
        case .largeVideos:
            return "Large Videos"
        case .livePhotos:
            return "Live Photos"
        case .savedImages:
            return "Saved Images"
        case .burstPhotos:
            return "Burst Photos"
        }
    }
    
    var subtitle: String {
        switch self {
        case .largeMedia:
            return "Videos & photos over 50MB"
        case .documents:
            return "Screenshots of text & notes"
        case .screenRecordings:
            return "Recorded screen videos"
        case .similarPhotos:
            return "Nearly identical shots"
        case .blurryPhotos:
            return "Out of focus & black screens"
        case .oldScreenshots:
            return "Screenshots older than 6 months"
        case .largeVideos:
            return "Videos over 100MB"
        case .livePhotos:
            return "Review large Live Photos"
        case .savedImages:
            return "Memes & downloaded images"
        case .burstPhotos:
            return "Keep best, delete the rest"
        }
    }
    
    var icon: String {
        switch self {
        case .largeMedia:
            return "arrow.up.circle.fill"
        case .documents:
            return "doc.text.fill"
        case .screenRecordings:
            return "record.circle"
        case .similarPhotos:
            return "square.on.square"
        case .blurryPhotos:
            return "camera.metering.none"
        case .oldScreenshots:
            return "clock.arrow.circlepath"
        case .largeVideos:
            return "film.stack"
        case .livePhotos:
            return "livephoto"
        case .savedImages:
            return "square.and.arrow.down"
        case .burstPhotos:
            return "square.stack.3d.down.right"
        }
    }
    
    var colorName: String {
        switch self {
        case .largeMedia:
            return "red"
        case .documents:
            return "blue"
        case .screenRecordings:
            return "green"
        case .similarPhotos:
            return "orange"
        case .blurryPhotos:
            return "purple"
        case .oldScreenshots:
            return "gray"
        case .largeVideos:
            return "red"
        case .livePhotos:
            return "yellow"
        case .savedImages:
            return "pink"
        case .burstPhotos:
            return "teal"
        }
    }
    
    /// Category grouping for Quick Wins vs Deep Clean
    var category: CleaningCategory {
        switch self {
        case .largeVideos, .oldScreenshots, .blurryPhotos, .screenRecordings:
            return .quickWins
        case .similarPhotos, .savedImages, .livePhotos, .burstPhotos, .largeMedia, .documents:
            return .deepClean
        }
    }
    
    /// Whether this mode typically provides high storage savings
    var isHighImpact: Bool {
        switch self {
        case .largeVideos, .similarPhotos, .livePhotos, .screenRecordings:
            return true
        default:
            return false
        }
    }
    
    /// Modes to show in the Quick Wins section
    static var quickWinsModes: [CleaningModeType] {
        [.largeVideos, .blurryPhotos, .oldScreenshots, .screenRecordings]
    }
    
    /// Modes to show in the Deep Clean section
    static var deepCleanModes: [CleaningModeType] {
        [.similarPhotos, .livePhotos, .savedImages, .burstPhotos]
    }
}
