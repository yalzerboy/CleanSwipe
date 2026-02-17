import Foundation
import Photos
import SwiftUI

enum PhotoFilter: Equatable, Codable, Hashable {
    case random
    case onThisDay
    case screenshots
    case year(Int)
    case favorites
    case shortVideos
    
    var displayName: LocalizedStringKey {
        switch self {
        case .random:
            return LocalizedStringKey("Random")
        case .onThisDay:
            return LocalizedStringKey("On this Day")
        case .screenshots:
            return LocalizedStringKey("Screenshots")
        case .year(let year):
            return LocalizedStringKey(String(year))
        case .favorites:
            return LocalizedStringKey("Favorites")
        case .shortVideos:
            return LocalizedStringKey("Short Videos")
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