//
//  DuplicateReviewViewModel.swift
//  Kage
//
//  Created by AI Assistant on 09/11/2025.
//

import Foundation
import Photos
import SwiftUI

@MainActor
final class DuplicateReviewViewModel: ObservableObject {
    @Published private(set) var groups: [DuplicateGroup] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var deletionInProgress = false
    @Published private(set) var deletionMessage: String?
    @Published private(set) var scanProgress: Double?
    @Published private(set) var isScanningWithProgress = false
    
    private(set) var lastLoadedPage: Int = -1
    private let pageSize: Int
    private let detectionService = DuplicateDetectionService.shared
    
    private var selection: [UUID: Set<String>] = [:]
    private var excludedAssetIDs: Set<String> = []
    private var currentScanID = UUID()
    
    init(pageSize: Int = 6) {
        self.pageSize = pageSize
    }
    
    // MARK: - Loading
    
    func reload(userInitiated: Bool = false) {
        Task { [weak self] in
            guard let self else { return }
            await self.performReload(userInitiated: userInitiated)
        }
    }
    
    private func performReload(userInitiated: Bool) async {
        let hasAccess = await ensurePhotoAccess()
        
        guard hasAccess else {
            groups = []
            selection = [:]
            hasMore = false
            errorMessage = "CleanSwipe needs access to your photo library to find duplicates. You can enable access in Settings."
            return
        }
        
        lastLoadedPage = -1
        groups = []
        selection = [:]
        hasMore = false
        errorMessage = nil
        if !userInitiated {
            excludedAssetIDs = []
        }
        currentScanID = UUID()
        await loadNextPage(forceRefresh: true, allowDeepScan: userInitiated)
    }
    
    private func ensurePhotoAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                    let granted = newStatus == .authorized || newStatus == .limited
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }
    
    func loadMoreIfNeeded(currentGroup group: DuplicateGroup?) {
        guard let group, hasMore else { return }
        let thresholdIndex = groups.index(groups.endIndex, offsetBy: -2, limitedBy: groups.startIndex) ?? groups.endIndex
        if groups.firstIndex(where: { $0.id == group.id }) == thresholdIndex {
            Task { await loadNextPage(forceRefresh: false) }
        }
    }
    
    func loadNextPage(forceRefresh: Bool, allowDeepScan: Bool = false) async {
        guard !isLoading else { return }
        
        if lastLoadedPage >= 0 {
            guard !isLoadingMore else { return }
            isLoadingMore = true
        } else {
            isLoading = true
        }
        
        let scanID = currentScanID
        let targetPage = lastLoadedPage + 1
        let shouldTrackProgress = targetPage == 0
        
        if shouldTrackProgress {
            isScanningWithProgress = true
            scanProgress = 0
        }
        
        defer {
            if scanID == currentScanID {
                isLoading = false
                isLoadingMore = false
                if shouldTrackProgress {
                    isScanningWithProgress = false
                    scanProgress = nil
                }
            }
        }
        
        do {
            let (clusters, moreAvailable) = try await detectionService.groups(page: targetPage,
                                                                              pageSize: pageSize,
                                                                              forceRefresh: forceRefresh && targetPage == 0,
                                                                              allowDeepScan: allowDeepScan && targetPage == 0,
                                                                              excludedAssetIDs: excludedAssetIDs,
                                                                              progressHandler: { [weak self, shouldTrackProgress, scanID] progress in
                                                                                guard shouldTrackProgress,
                                                                                      let self else { return }
                                                                                await MainActor.run { [weak self] in
                                                                                    guard let self,
                                                                                          scanID == self.currentScanID else { return }
                                                                                    self.scanProgress = progress
                                                                                    self.isScanningWithProgress = true
                                                                                }
                                                                              })
            guard scanID == currentScanID else { return }
            let converted = await convert(clusters: clusters)
            var newGroups: [DuplicateGroup] = []
            if targetPage == 0 {
                groups = converted
                newGroups = converted
            } else {
                let existingIDs = Set(groups.map(\.id))
                newGroups = converted.filter { !existingIDs.contains($0.id) }
                groups.append(contentsOf: newGroups)
            }
            hasMore = moreAvailable
            lastLoadedPage = targetPage
            updateDefaultSelection(for: newGroups)
            if shouldTrackProgress {
                await MainActor.run {
                    guard scanID == currentScanID else { return }
                    self.scanProgress = 1.0
                }
            }
        } catch {
            guard scanID == currentScanID else { return }
            errorMessage = error.localizedDescription
        }
    }
    
    private func convert(clusters: [DuplicateDetectionService.DuplicateCluster]) async -> [DuplicateGroup] {
        guard !clusters.isEmpty else { return [] }
        let allIDs = clusters.flatMap { $0.assetIDs }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: allIDs, options: nil)
        var assetsByID: [String: PHAsset] = [:]
        fetchResult.enumerateObjects { asset, _, _ in
            assetsByID[asset.localIdentifier] = asset
        }
        
        return clusters.compactMap { cluster in
            let items: [DuplicateAssetItem] = cluster.assetIDs.compactMap { identifier in
                guard let asset = assetsByID[identifier] else { return nil }
                let distance = cluster.distances[identifier] ?? 0
                return DuplicateAssetItem(
                    id: identifier,
                    asset: asset,
                    distanceScore: distance,
                    isPrimary: identifier == cluster.representativeAssetID
                )
            }
            
            guard items.count > 1 else { return nil }
            let assetIDs = items.map(\.id)
            if !assetIDs.contains(where: { !excludedAssetIDs.contains($0) }) {
                return nil
            }
            let groupKind: DuplicateGroupKind = {
                switch cluster.kind {
                case .exact:
                    return .exact
                case .verySimilar:
                    return .verySimilar
                }
            }()
            
            return DuplicateGroup(
                id: cluster.id,
                kind: groupKind,
                assets: items,
                representativeDate: cluster.representativeCreationDate
            )
        }
    }
    
    private func updateDefaultSelection(for newGroups: [DuplicateGroup]) {
        for group in newGroups {
            guard selection[group.id] == nil else { continue }
            let defaultSelected = Set(group.assets.filter { !$0.isPrimary }.map(\.id))
            selection[group.id] = defaultSelected
        }
    }
    
    // MARK: - Selection
    
    func isSelected(assetID: String, in groupID: UUID) -> Bool {
        selection[groupID]?.contains(assetID) ?? false
    }
    
    func toggleSelection(assetID: String, groupID: UUID) {
        guard var set = selection[groupID] else { return }
        if set.contains(assetID) {
            set.remove(assetID)
        } else {
            set.insert(assetID)
        }
        selection[groupID] = set
        objectWillChange.send()
    }
    
    func selectAll(in groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        selection[groupID] = Set(group.assets.map(\.id))
        objectWillChange.send()
    }
    
    func deselectAll(in groupID: UUID) {
        selection[groupID] = []
        objectWillChange.send()
    }
    
    func totalSelectedCount() -> Int {
        selection.reduce(0) { partialResult, entry in
            partialResult + entry.value.count
        }
    }
    
    func selectedAssets(in groupID: UUID) -> [DuplicateAssetItem] {
        guard let group = groups.first(where: { $0.id == groupID }) else { return [] }
        let selectedIDs = selection[groupID] ?? []
        return group.assets.filter { selectedIDs.contains($0.id) }
    }
    
    // MARK: - Deletion
    
    func deleteSelected() async -> Bool {
        let allSelectedIDs = Set(selection.values.flatMap { $0 })
        guard !allSelectedIDs.isEmpty else {
            deletionMessage = "Select photos to delete."
            return false
        }
        
        deletionInProgress = true
        defer { deletionInProgress = false }
        
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: Array(allSelectedIDs), options: nil)
        var success = false
        var deletionError: Error?
        
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(fetchResult)
            }, completionHandler: { completed, error in
                success = completed
                deletionError = error
                continuation.resume()
            })
        }
        
        if success {
            removeAssets(with: allSelectedIDs)
            await detectionService.invalidateCache()
            deletionMessage = "Deleted \(allSelectedIDs.count) photos."
            excludedAssetIDs.subtract(allSelectedIDs)

            // Track photo deletion analytics
            AnalyticsManager.shared.trackPhotoDeleted(count: allSelectedIDs.count, feature: "duplicates")
        } else {
            if let deletionError {
                deletionMessage = deletionError.localizedDescription
            } else {
                deletionMessage = "Unable to delete photos."
            }
        }
        
        return success
    }
    
    private func removeAssets(with identifiers: Set<String>) {
        groups = groups.compactMap { group in
            let remainingAssets = group.assets.filter { !identifiers.contains($0.id) }
            if remainingAssets.count < 2 {
                selection[group.id] = nil
                return nil
            }
            
            selection[group.id]?.subtract(identifiers)
            return DuplicateGroup(
                id: group.id,
                kind: group.kind,
                assets: remainingAssets,
                representativeDate: group.representativeDate
            )
        }
        hasMore = false
        lastLoadedPage = groups.isEmpty ? -1 : lastLoadedPage
        excludedAssetIDs.subtract(identifiers)
    }
    
    func requestMoreDuplicates() {
        let currentAssetIDs = groups.flatMap { $0.assets.map(\.id) }
        excludedAssetIDs.formUnion(currentAssetIDs)
        currentScanID = UUID()
        reload(userInitiated: true)
    }
    
    func cancelScanning() {
        currentScanID = UUID()
        isLoading = false
        isLoadingMore = false
        isScanningWithProgress = false
        scanProgress = nil
    }

    func cancelDeletionIfPossible() {
        // Note: Deletion operations using PHPhotoLibrary can't be cancelled once started,
        // but we can at least reset the UI state to prevent further operations
        if deletionInProgress {
            deletionInProgress = false
        }
    }
}


