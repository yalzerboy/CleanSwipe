//
//  DuplicateDetectionService.swift
//  Kage
//
//  Created by AI Assistant on 09/11/2025.
//

import Foundation
import Photos
import Vision
import UIKit
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

    // Sequential scanning state - track total photos scanned so far
    private(set) var totalPhotosScanned: Int = 0

    // Smaller batch size for faster initial results
    // With parallel processing and early termination, we can use smaller batches
    private let batchSize = 1000  // Smaller batches for faster results
    
    private init() {}
    
    // MARK: - Public API
    
    func groups(page: Int,
                pageSize: Int,
                forceRefresh: Bool = false,
                allowDeepScan: Bool = false,
                excludedAssetIDs: Set<String> = [],
                findMoreDuplicates: Bool = false,
                progressHandler: (@Sendable (Double) async -> Void)? = nil) async throws -> ([DuplicateCluster], Bool) {
        let shouldRefresh = cachedClusters.isEmpty || forceRefresh || shouldRefreshClusters() || findMoreDuplicates
        if shouldRefresh {
            try await refreshClusters(isFreshScan: forceRefresh, forceDeepScan: allowDeepScan, findMoreDuplicates: findMoreDuplicates, progressHandler: progressHandler)
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
        // Reset sequential scanning state
        totalPhotosScanned = 0
    }

    func hasCachedResults() -> Bool {
        return !cachedClusters.isEmpty
    }
    
    // MARK: - Cluster Refresh
    
    private struct ScanOutcome {
        let clusters: [DuplicateCluster]
        let scannedAssetCount: Int
    }
    
    private func refreshClusters(isFreshScan: Bool = false,
                                 forceDeepScan: Bool,
                                 exactThreshold: Float? = nil,  // Will be set based on iOS version
                                 similarThreshold: Float? = nil, // Will be set based on iOS version
                                 findMoreDuplicates: Bool = false,
                                 progressHandler: (@Sendable (Double) async -> Void)?) async throws {
        // Set thresholds based on iOS version
        // iOS 17+: normalized vectors, distances 0-2.0 (use lower thresholds)
        // iOS 16: non-normalized vectors, distances 0-40.0 (use higher thresholds)
        let (exactThresh, similarThresh): (Float, Float)
        if #available(iOS 17.0, *) {
            // iOS 17+: Based on research, distances are typically 0-2.0
            // Based on actual observed distances (min=0.086, max=1.36), using lenient thresholds
            exactThresh = exactThreshold ?? 0.5   // iOS 17: normalized, distances 0-2.0
            similarThresh = similarThreshold ?? 0.9
            logger.info("Using iOS 17+ thresholds: exact=\(exactThresh), similar=\(similarThresh)")
        } else {
            // iOS 16: distances are typically 0-40.0
            exactThresh = exactThreshold ?? 15.0  // iOS 16: non-normalized, distances 0-40.0
            similarThresh = similarThreshold ?? 25.0
            logger.info("Using iOS 16 thresholds: exact=\(exactThresh), similar=\(similarThresh)")
        }
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

        // Sequential scanning: determine offset for this scan
        let scanOffset: Int
        if isFreshScan {
            // Fresh scan - start from beginning
            scanOffset = 0
            totalPhotosScanned = 0
        } else {
            // Continue from where we left off (incremental scanning)
            scanOffset = totalPhotosScanned
        }

        let iosVersion = ProcessInfo.processInfo.operatingSystemVersion
        logger.info("Starting sequential scan: offset \(scanOffset), batch size \(self.batchSize), iOS \(iosVersion.majorVersion).\(iosVersion.minorVersion), thresholds: exact=\(exactThresh), similar=\(similarThresh)")

        // Scan with fixed batch size for consistent performance
        let outcome = try await performSequentialScan(offset: scanOffset,
                                                     limit: batchSize,
                                                     exactThreshold: exactThresh,
                                                     similarThreshold: similarThresh,
                                                     progressHandler: progressHandler)

        logger.info("Sequential scan completed: found \(outcome.clusters.count) clusters from \(outcome.scannedAssetCount) assets (exactThreshold: \(exactThresh), similarThreshold: \(similarThresh))")
        cachedClusters = outcome.clusters.sorted { lhs, rhs in
            let lhsDate = lhs.representativeCreationDate ?? Date.distantPast
            let rhsDate = rhs.representativeCreationDate ?? Date.distantPast
            return lhsDate > rhsDate
        }
        if let progressHandler {
            await progressHandler(1.0)
        }

        // Update total photos scanned (approximate, since we're doing random batches)
        totalPhotosScanned += outcome.scannedAssetCount

        lastScanDate = Date()
    }
    
    private func performSequentialScan(offset: Int,
                                      limit: Int,
                                      exactThreshold: Float,
                                      similarThreshold: Float,
                                      progressHandler: (@Sendable (Double) async -> Void)?) async throws -> ScanOutcome {
        let assets = await fetchAssets(offset: offset, limit: limit)
        guard !assets.isEmpty else {
            return ScanOutcome(clusters: [], scannedAssetCount: 0)
        }
        
        // Parallel descriptor generation for much faster processing
        var descriptors: [String: FeatureDescriptor] = [:]
        descriptors.reserveCapacity(assets.count)
        
        // Process descriptors in parallel for much faster processing
        // Use controlled concurrency to avoid overwhelming the system
        // With smaller images (512px max dimension), we can process more in parallel
        let maxConcurrency = 8  // Process 8 images in parallel
        var processedCount = 0
        
        try await withThrowingTaskGroup(of: (String, FeatureDescriptor?).self) { group in
            var assetIndex = 0
            
            // Start initial batch of tasks
            for _ in 0..<min(maxConcurrency, assets.count) {
                guard assetIndex < assets.count else { break }
                let asset = assets[assetIndex]
                assetIndex += 1
                
                group.addTask { [weak self] in
                    guard let self else { return (asset.localIdentifier, nil) }
                    do {
                        try Task.checkCancellation()
                        if let descriptor = try await self.descriptor(for: asset) {
                            return (asset.localIdentifier, descriptor)
                        }
                    } catch {
                        // Log error but continue
                    }
                    return (asset.localIdentifier, nil)
                }
            }
            
            // Process results and add new tasks as they complete
            while let result = try await group.next() {
                try Task.checkCancellation()
                
                let (assetID, descriptor) = result
                if let descriptor = descriptor {
                    descriptors[assetID] = descriptor
                }
                processedCount += 1
                
                // Add next task if there are more assets
                if assetIndex < assets.count {
                    let asset = assets[assetIndex]
                    assetIndex += 1
                    
                    group.addTask { [weak self] in
                        guard let self else { return (asset.localIdentifier, nil) }
                        do {
                            try Task.checkCancellation()
                            if let descriptor = try await self.descriptor(for: asset) {
                                return (asset.localIdentifier, descriptor)
                            }
                        } catch {
                            // Log error but continue
                        }
                        return (asset.localIdentifier, nil)
                    }
                }
                
                // Update progress
                if let progressHandler {
                    let progress = Double(processedCount) / Double(assets.count)
                    await progressHandler(min(progress * 0.7, 0.7))
                }
            }
        }
        
        let clusters = try await buildClusters(from: assets,
                                               descriptors: descriptors,
                                               exactThreshold: exactThreshold,
                                               similarThreshold: similarThreshold,
                                               progressHandler: progressHandler,
                                               processedDescriptorCount: assets.count,
                                               maxClusters: 8)  // Early termination when we find 8 clusters
        
        return ScanOutcome(clusters: clusters, scannedAssetCount: assets.count)
    }
    
    private func shouldRefreshClusters(refreshInterval: TimeInterval = 60 * 15) -> Bool {
        guard let lastScanDate else { return true }
        return Date().timeIntervalSince(lastScanDate) > refreshInterval
    }
    
    // MARK: - Asset Fetching

    private func getTotalPhotoCount() async -> Int {
        await MainActor.run {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
            options.includeHiddenAssets = false
            let fetchResult = PHAsset.fetchAssets(with: .image, options: options)
            return fetchResult.count
        }
    }

    private func fetchAssets(offset: Int, limit: Int) async -> [PHAsset] {
        await MainActor.run {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.includeHiddenAssets = false
            // Fetch enough assets to skip offset and get limit more
            options.fetchLimit = offset + limit

            // Only filter for images
            options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)

            var assets: [PHAsset] = []
            let fetchResult = PHAsset.fetchAssets(with: .image, options: options)

            // Skip the first 'offset' assets and take the next 'limit' assets
            var currentIndex = 0
            fetchResult.enumerateObjects { asset, _, stop in
                if currentIndex >= offset {
                    assets.append(asset)
                    if assets.count >= limit {
                        stop.pointee = true
                    }
                }
                currentIndex += 1
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
                               maxGroupSize: Int = 8,
                               maxClusters: Int = Int.max) async throws -> [DuplicateCluster] {
        var clusters: [DuplicateCluster] = []
        var consumedIdentifiers = Set<String>()
        var totalComparisons = 0
        var matchesFound = 0
        var minDistance: Float = Float.greatestFiniteMagnitude
        var maxDistance: Float = 0
        
        for (index, asset) in assets.enumerated() {
            // Early termination: if we've found enough clusters, stop processing
            if clusters.count >= maxClusters {
                break
            }
            
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
                totalComparisons += 1
                minDistance = min(minDistance, distance)
                maxDistance = max(maxDistance, distance)
                
                if distance <= similarThreshold {
                    matchesFound += 1
                    members.append((candidate, distance))
                    
                    // Early termination: if we found an exact match and have enough members, stop searching
                    if distance <= exactThreshold && members.count >= 3 {
                        // Found exact match with a few others, likely enough - stop searching
                        break
                    }
                    
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
            
            // Early termination: if we've found enough clusters, stop processing
            if clusters.count >= maxClusters {
                logger.info("Early termination: found \(clusters.count) clusters, stopping search")
                break
            }
            
            if let progressHandler {
                let base = 0.7
                let remaining = 0.3
                let progress = base + (Double(index + 1) / Double(processedDescriptorCount)) * remaining
                await progressHandler(min(max(progress, base), 1.0))
            }
        }
        
        // Log stats to help debug duplicate detection
        logger.info("buildClusters: \(clusters.count) clusters from \(totalComparisons) comparisons, \(matchesFound) matches, distances: min=\(minDistance), max=\(maxDistance), thresholds: exact=\(exactThreshold), similar=\(similarThreshold)")
        
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
        // Use optimal image size for feature extraction - 512px on longest side balances performance and accuracy
        // This is the recommended size for Vision framework feature extraction
        let maxDimension: CGFloat = 512
        let targetSize: CGSize
        if asset.pixelWidth > asset.pixelHeight {
            let aspectRatio = CGFloat(asset.pixelHeight) / CGFloat(asset.pixelWidth)
            targetSize = CGSize(width: maxDimension, height: maxDimension * aspectRatio)
        } else {
            let aspectRatio = CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
            targetSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(data: Data, orientation: CGImagePropertyOrientation)?, Error>) in
            let options = PHImageRequestOptions()
            options.version = .current
            options.deliveryMode = .fastFormat  // Fastest mode - we don't need high quality
            options.resizeMode = .fast
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { image, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let image = image else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Convert to JPEG without alpha to avoid AlphaLast warning and reduce memory
                // Create a new image context without alpha channel
                let format = UIGraphicsImageRendererFormat()
                format.opaque = true  // No alpha channel for JPEG
                format.scale = image.scale
                
                let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
                let jpegImage = renderer.jpegData(withCompressionQuality: 0.5) { context in
                    image.draw(in: CGRect(origin: .zero, size: image.size))
                }
                
                // Image is already correctly oriented from requestImage, use .up
                let orientation: CGImagePropertyOrientation = .up
                continuation.resume(returning: (jpegImage, orientation))
            }
        }
    }
    
    private func generateFeatureDescriptor(for asset: PHAsset,
                                           imageData: Data,
                                           orientation: CGImagePropertyOrientation) throws -> FeatureDescriptor {
        let handler = VNImageRequestHandler(data: imageData, orientation: orientation, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()
        
        // Use revision 2 (iOS 17+) for normalized feature vectors (distances 0-2.0)
        // This provides more consistent and meaningful distance comparisons
        if #available(iOS 17.0, *) {
            request.revision = VNGenerateImageFeaturePrintRequestRevision2
        }
        // iOS 16 and below will use revision 1 (distances 0-40.0) automatically
        
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


