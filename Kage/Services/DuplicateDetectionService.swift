//
//  DuplicateDetectionService.swift
//  Kage
//
//  Created by AI Assistant on 09/11/2025.
//

import Foundation
import Photos
import Vision
import os.log

actor DuplicateDetectionService {
    static let shared = DuplicateDetectionService()
    
    enum DetectionError: Error {
        case imageDataUnavailable
        case featurePrintUnavailable
    }
    
    enum GroupKind: String, Codable {
        case exact
        case verySimilar
    }
    
    struct DuplicateCluster {
        let id: UUID
        let representativeAssetID: String
        let assetIDs: [String]
        let distances: [String: Float]
        let kind: GroupKind
        let representativeCreationDate: Date?
    }
    
    private struct FeatureDescriptor {
        let assetIdentifier: String
        let observation: VNFeaturePrintObservation
        let creationDate: Date?
        let updatedAt: Date
    }
    
    private let logger = Logger(subsystem: "com.yalun.CleanSwipe", category: "DuplicateDetection")
    
    private var memoryCache: [String: FeatureDescriptor] = [:]
    private var cachedClusters: [DuplicateCluster] = []
    private var lastScanDate: Date?
    private var isScanning = false
    
    private let baseScanLimit = 800
    private let maxScanLimit = 6400
    private var currentScanLimit = 800
    private let scanExpansionFactor = 2
    
    private init() {}
    
    // MARK: - Public API
    
    func groups(page: Int,
                pageSize: Int,
                forceRefresh: Bool = false,
                allowDeepScan: Bool = false,
                excludedAssetIDs: Set<String> = [],
                progressHandler: (@Sendable (Double) async -> Void)? = nil) async throws -> ([DuplicateCluster], Bool) {
        if cachedClusters.isEmpty || forceRefresh || shouldRefreshClusters() {
            try await refreshClusters(forceDeepScan: allowDeepScan, progressHandler: progressHandler)
        } else {
            if let progressHandler {
                await progressHandler(1.0)
            }
        }
        
        let clustersForPaging: [DuplicateCluster]
        if excludedAssetIDs.isEmpty {
            clustersForPaging = cachedClusters
        } else {
            clustersForPaging = cachedClusters.filter { cluster in
                cluster.assetIDs.contains { !excludedAssetIDs.contains($0) }
            }
        }
        
        let start = max(0, page * pageSize)
        guard start < clustersForPaging.count else {
            return ([], false)
        }
        let end = min(start + pageSize, clustersForPaging.count)
        let slice = Array(clustersForPaging[start..<end])
        let hasMore = end < clustersForPaging.count
        return (slice, hasMore)
    }
    
    func invalidateCache() {
        cachedClusters = []
        lastScanDate = nil
        memoryCache.removeAll()
        currentScanLimit = baseScanLimit
    }
    
    // MARK: - Cluster Refresh
    
    private struct ScanOutcome {
        let clusters: [DuplicateCluster]
        let scannedAssetCount: Int
    }
    
    private func refreshClusters(forceDeepScan: Bool,
                                 exactThreshold: Float = 0.075,
                                 similarThreshold: Float = 0.13,
                                 progressHandler: (@Sendable (Double) async -> Void)?) async throws {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        
        if let progressHandler {
            await progressHandler(0.0)
        }
        
        try Task.checkCancellation()
        
        let authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            cachedClusters = []
            lastScanDate = Date()
            logger.info("Skipping duplicate refresh because photo access is not granted.")
            if let progressHandler {
                await progressHandler(1.0)
            }
            return
        }
        
        var attemptLimit = forceDeepScan ? max(baseScanLimit, currentScanLimit) : baseScanLimit
        var outcome = ScanOutcome(clusters: [], scannedAssetCount: 0)
        
        repeat {
            try Task.checkCancellation()
            outcome = try await performScan(limit: attemptLimit,
                                            exactThreshold: exactThreshold,
                                            similarThreshold: similarThreshold,
                                            progressHandler: progressHandler)
            
            let shouldExpand = forceDeepScan
                && outcome.clusters.isEmpty
                && outcome.scannedAssetCount >= attemptLimit
                && attemptLimit < maxScanLimit
            
            if shouldExpand {
                let nextLimit = min(maxScanLimit, attemptLimit * scanExpansionFactor)
                logger.info("Duplicate scan produced no results. Expanding search limit from \(attemptLimit, privacy: .public) to \(nextLimit, privacy: .public).")
                if nextLimit == attemptLimit {
                    break
                }
                attemptLimit = nextLimit
                continue
            }
            
            break
        } while true
        cachedClusters = outcome.clusters.sorted { lhs, rhs in
            let lhsDate = lhs.representativeCreationDate ?? Date.distantPast
            let rhsDate = rhs.representativeCreationDate ?? Date.distantPast
            return lhsDate > rhsDate
        }
        if let progressHandler {
            await progressHandler(1.0)
        }
        if forceDeepScan {
            currentScanLimit = max(baseScanLimit, min(attemptLimit, maxScanLimit))
        }
        lastScanDate = Date()
    }
    
    private func performScan(limit: Int,
                             exactThreshold: Float,
                             similarThreshold: Float,
                             progressHandler: (@Sendable (Double) async -> Void)?) async throws -> ScanOutcome {
        let assets = await fetchRecentAssets(limit: limit)
        guard !assets.isEmpty else {
            return ScanOutcome(clusters: [], scannedAssetCount: 0)
        }
        
        var descriptors: [String: FeatureDescriptor] = [:]
        descriptors.reserveCapacity(assets.count)
        
        for (index, asset) in assets.enumerated() {
            try Task.checkCancellation()
            if let descriptor = try await descriptor(for: asset) {
                descriptors[asset.localIdentifier] = descriptor
            }
            if let progressHandler {
                let progress = Double(index + 1) / Double(assets.count)
                await progressHandler(min(progress * 0.7, 0.7))
            }
        }
        
        let clusters = try await buildClusters(from: assets,
                                               descriptors: descriptors,
                                               exactThreshold: exactThreshold,
                                               similarThreshold: similarThreshold,
                                               progressHandler: progressHandler,
                                               processedDescriptorCount: assets.count)
        
        return ScanOutcome(clusters: clusters, scannedAssetCount: assets.count)
    }
    
    private func shouldRefreshClusters(refreshInterval: TimeInterval = 60 * 15) -> Bool {
        guard let lastScanDate else { return true }
        return Date().timeIntervalSince(lastScanDate) > refreshInterval
    }
    
    // MARK: - Asset Fetching
    
    private func fetchRecentAssets(limit: Int) async -> [PHAsset] {
        await MainActor.run {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
            options.includeHiddenAssets = false
            options.fetchLimit = limit
            
            var assets: [PHAsset] = []
            let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
            fetchResult.enumerateObjects { asset, _, stop in
                assets.append(asset)
                if assets.count >= limit {
                    stop.pointee = true
                }
            }
            return assets
        }
    }
    
    // MARK: - Cluster Builder
    
    private func buildClusters(from assets: [PHAsset],
                               descriptors: [String: FeatureDescriptor],
                               exactThreshold: Float,
                               similarThreshold: Float,
                               progressHandler: (@Sendable (Double) async -> Void)?,
                               processedDescriptorCount: Int,
                               maxGroupSize: Int = 8) async throws -> [DuplicateCluster] {
        var clusters: [DuplicateCluster] = []
        var consumedIdentifiers = Set<String>()
        
        for (index, asset) in assets.enumerated() {
            let assetID = asset.localIdentifier
            guard !consumedIdentifiers.contains(assetID),
                  let baseDescriptor = descriptors[assetID] else {
                continue
            }
            
            var members: [(asset: PHAsset, distance: Float)] = []
            
            for innerIndex in (index + 1)..<assets.count {
                let candidate = assets[innerIndex]
                let candidateID = candidate.localIdentifier
                
                guard !consumedIdentifiers.contains(candidateID),
                      let candidateDescriptor = descriptors[candidateID] else {
                    continue
                }
                
                let distance = try computeDistance(between: baseDescriptor, and: candidateDescriptor)
                if distance <= similarThreshold {
                    members.append((candidate, distance))
                    if members.count >= (maxGroupSize - 1) {
                        break
                    }
                }
            }
            
            guard !members.isEmpty else {
                continue
            }
            
            let kind: GroupKind
            if members.contains(where: { $0.distance <= exactThreshold }) {
                kind = .exact
            } else {
                kind = .verySimilar
            }
            
            var assetIDs = [assetID]
            var distances: [String: Float] = [:]
            distances[assetID] = 0
            
            for member in members {
                let id = member.asset.localIdentifier
                assetIDs.append(id)
                distances[id] = member.distance
                consumedIdentifiers.insert(id)
            }
            consumedIdentifiers.insert(assetID)
            
            let cluster = DuplicateCluster(
                id: UUID(),
                representativeAssetID: assetID,
                assetIDs: assetIDs,
                distances: distances,
                kind: kind,
                representativeCreationDate: asset.creationDate
            )
            clusters.append(cluster)
            
            if let progressHandler {
                let base = 0.7
                let remaining = 0.3
                let progress = base + (Double(index + 1) / Double(processedDescriptorCount)) * remaining
                await progressHandler(min(max(progress, base), 1.0))
            }
        }
        
        return clusters
    }
    
    // MARK: - Feature Descriptors
    
    private func descriptor(for asset: PHAsset) async throws -> FeatureDescriptor? {
        let assetID = asset.localIdentifier
        if let cached = memoryCache[assetID] {
            return cached
        }
        
        guard let dataPayload = try await requestImageData(for: asset) else {
            logger.error("Failed to obtain image data for asset \(assetID, privacy: .public)")
            return nil
        }
        
        let descriptor = try generateFeatureDescriptor(for: asset, imageData: dataPayload.data, orientation: dataPayload.orientation)
        memoryCache[assetID] = descriptor
        return descriptor
    }
    
    private func requestImageData(for asset: PHAsset) async throws -> (data: Data, orientation: CGImagePropertyOrientation)? {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, orientation, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }
                
                continuation.resume(returning: (data, orientation))
            }
        }
    }
    
    private func generateFeatureDescriptor(for asset: PHAsset,
                                           imageData: Data,
                                           orientation: CGImagePropertyOrientation) throws -> FeatureDescriptor {
        let handler = VNImageRequestHandler(data: imageData, orientation: orientation, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()
        try handler.perform([request])
        
        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw DetectionError.featurePrintUnavailable
        }
        
        return FeatureDescriptor(
            assetIdentifier: asset.localIdentifier,
            observation: observation,
            creationDate: asset.creationDate,
            updatedAt: Date()
        )
    }
    
    private func computeDistance(between lhs: FeatureDescriptor,
                                 and rhs: FeatureDescriptor) throws -> Float {
        var distance: Float = 0
        try lhs.observation.computeDistance(&distance, to: rhs.observation)
        return distance
    }
    
}


