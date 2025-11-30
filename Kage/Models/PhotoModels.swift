import Foundation
import Photos

enum PhotoFilter: Equatable, Codable, Hashable {
    case random
    case onThisDay
    case screenshots
    case year(Int)
    case favorites
    case shortVideos
    
    var displayName: String {
        switch self {
        case .random:
            return "Random"
        case .onThisDay:
            return "On this Day"
        case .screenshots:
            return "Screenshots"
        case .year(let year):
            return String(year)
        case .favorites:
            return "Favorites"
        case .shortVideos:
            return "Short Videos"
        }
    }
    
    /// Returns a string representation suitable for analytics tracking
    var analyticsValue: String {
        switch self {
        case .random:
            return "random"
        case .onThisDay:
            return "on_this_day"
        case .screenshots:
            return "screenshots"
        case .year(let year):
            return "year_\(year)"
        case .favorites:
            return "favorites"
        case .shortVideos:
            return "short_videos"
        }
    }
}

enum SwipeAction: String, Codable {
    case keep
    case delete
}

struct SwipedPhoto {
    let asset: PHAsset
    var action: SwipeAction
}

// Codable version for persistence
struct SwipedPhotoPersisted: Codable {
    let assetLocalIdentifier: String
    let action: SwipeAction
} 