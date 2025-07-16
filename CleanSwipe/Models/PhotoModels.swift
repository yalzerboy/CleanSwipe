import Foundation
import Photos

enum PhotoFilter: Equatable {
    case random
    case year(Int)
}

enum SwipeAction {
    case keep
    case delete
}

struct SwipedPhoto {
    let asset: PHAsset
    var action: SwipeAction
} 