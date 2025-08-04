import Foundation
import Photos

enum PhotoFilter: Equatable, Codable, Hashable {
    case random
    case onThisDay
    case screenshots
    case year(Int)
    
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