//
//  DuplicateModels.swift
//  Kage
//
//  Created by AI Assistant on 09/11/2025.
//

import Foundation
import Photos

enum DuplicateGroupKind {
    case exact
    case verySimilar
    
    var title: String {
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
    
    var subtitle: String {
        let count = assets.count
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        
        var components: [String] = []
        components.append("\(count) photos")
        if let date = representativeDate {
            components.append(formatter.string(from: date))
        }
        return components.joined(separator: " • ")
    }
    
    var primaryAsset: DuplicateAssetItem? {
        assets.first(where: { $0.isPrimary }) ?? assets.first
    }
}


