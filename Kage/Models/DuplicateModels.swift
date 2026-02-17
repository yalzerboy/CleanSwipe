//
//  DuplicateModels.swift
//  Kage
//
//  Created by AI Assistant on 09/11/2025.
//

import Foundation
import Photos
import SwiftUI

enum DuplicateGroupKind {
    case exact
    case verySimilar
    
    var title: LocalizedStringKey {
        switch self {
        case .exact:
            return "Exact duplicates"
        case .verySimilar:
            return "Very similar"
        }
    }
}

struct DuplicateAssetItem: Identifiable, Hashable {
    let id: String
    let asset: PHAsset
    let distanceScore: Float
    let isPrimary: Bool
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: DuplicateAssetItem, rhs: DuplicateAssetItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct DuplicateGroup: Identifiable {
    let id: UUID
    let kind: DuplicateGroupKind
    let assets: [DuplicateAssetItem]
    let representativeDate: Date?
    
    var subtitle: LocalizedStringKey {
        let count = assets.count
        return "\(count) photos"
    }
    
    var primaryAsset: DuplicateAssetItem? {
        assets.first(where: { $0.isPrimary }) ?? assets.first
    }
}


