import Foundation
import Photos

enum PhotoFilter: Equatable, Codable, Hashable {
    case random
    case year(Int)
    
    var displayName: String {
        switch self {
        case .random:
            return "Random"
        case .year(let year):
            return String(year)
        }
    }
}

enum SwipeAction {
    case keep
    case delete
}

struct SwipedPhoto {
    let asset: PHAsset
    var action: SwipeAction
} 