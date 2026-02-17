import Foundation
import Photos

/// Cache structure for persisting Smart Cleanup scan stats
struct SmartCleanupCache: Codable {
    var lastScanTimestamp: Date?
    var modeStats: [String: ModeStats]
    
    struct ModeStats: Codable {
        let assetCount: Int
        let totalSize: Int64
        let assetIdentifiers: [String] // PHAsset localIdentifiers for quick lookup
    }
    
    var reviewedAssetIDs: Set<String> = []
    
    init() {
        self.lastScanTimestamp = nil
        self.modeStats = [:]
    }
    
    /// Check if cache is still valid (less than 1 hour old)
    var isValid: Bool {
        guard let timestamp = lastScanTimestamp else { return false }
        let oneHour: TimeInterval = 3600
        return Date().timeIntervalSince(timestamp) < oneHour
    }
}

/// Service for detecting and calculating storage for smart cleaning modes
final class SmartCleaningService {
    static let shared = SmartCleaningService()
    
    private let imageManager: PHCachingImageManager
    
    /// Threshold for large media (50MB)
    private let largeMediaThreshold: Int64 = 50 * 1024 * 1024
    
    /// Short video duration threshold (10 seconds)
    private let shortVideoDuration: Double = 10.0
    
    /// UserDefaults key for cache
    private let cacheKey = "SmartCleanupCacheV1"
    
    /// In-memory cache for assets (not persisted, rebuilt from identifiers)
    private var cachedAssets: [CleaningModeType: [PHAsset]] = [:]
    
    /// Flag to indicate if background preload is in progress
    private var isPreloading = false
    
    /// Cached stats from UserDefaults
    private var cachedStats: SmartCleanupCache?
    
    private init() {
        self.imageManager = PHCachingImageManager()
        loadCachedStats()
    }
    
    // MARK: - Large Media Detection
    
    /// Finds large videos and photos (>50MB)
    func findLargeMedia(limit: Int = 50, limitMultiplier: Int = 1) async -> (assets: [PHAsset], totalSize: Int64) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return ([], 0)
        }
        
        return await Task.detached(priority: .userInitiated) { [self] in
            var results: [(asset: PHAsset, size: Int64)] = []
            
            // Fetch all videos first (most likely to be large)
            let videoOptions = PHFetchOptions()
            videoOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let videos = PHAsset.fetchAssets(with: .video, options: videoOptions)
            
            let scanLimit = 500 * limitMultiplier
            videos.enumerateObjects { asset, index, stop in
                if index >= scanLimit {
                    stop.pointee = true
                    return
                }
                
                if self.cachedStats?.reviewedAssetIDs.contains(asset.localIdentifier) == true { return }
                
                if let resources = PHAssetResource.assetResources(for: asset).first {
                    if let size = resources.value(forKey: "fileSize") as? Int64, size >= self.largeMediaThreshold {
                        results.append((asset, size))
                    }
                }
                if results.count >= limit * 2 {
                    stop.pointee = true
                }
            }
            
            // Also check photos
            let photoOptions = PHFetchOptions()
            photoOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let photos = PHAsset.fetchAssets(with: .image, options: photoOptions)
            
            let photoScanLimit = 1000 * limitMultiplier
            photos.enumerateObjects { asset, index, stop in
                if index >= photoScanLimit {
                    stop.pointee = true
                    return
                }
                
                if self.cachedStats?.reviewedAssetIDs.contains(asset.localIdentifier) == true { return }
                
                if let resources = PHAssetResource.assetResources(for: asset).first {
                    if let size = resources.value(forKey: "fileSize") as? Int64, size >= self.largeMediaThreshold {
                        results.append((asset, size))
                    }
                }
                if results.count >= limit * 3 {
                    stop.pointee = true
                }
            }
            
            // Sort by size descending and take top results
            results.sort { $0.size > $1.size }
            let topResults = Array(results.prefix(limit))
            let totalSize = topResults.reduce(0) { $0 + $1.size }
            
            return (topResults.map { $0.asset }, totalSize)
        }.value
    }
    
    // MARK: - Screen Recordings Detection
    
    /// Finds screen recordings
    func findScreenRecordings(limit: Int = 50, limitMultiplier: Int = 1) async -> (assets: [PHAsset], totalSize: Int64) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return ([], 0)
        }
        
        return await Task.detached(priority: .userInitiated) { [self] in
            var results: [PHAsset] = []
            var totalSize: Int64 = 0
            
            let options = PHFetchOptions()
            options.predicate = NSPredicate(
                format: "mediaType = %d AND (mediaSubtypes & %d) != 0",
                PHAssetMediaType.video.rawValue,
                PHAssetMediaSubtype.videoScreenRecording.rawValue
            )
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            
            let screenRecordings = PHAsset.fetchAssets(with: options)
            
            let scanLimit = 500 * limitMultiplier
            screenRecordings.enumerateObjects { asset, index, stop in
                if index >= scanLimit {
                    stop.pointee = true
                    return
                }
                
                let assetID = asset.localIdentifier
                if self.cachedStats?.reviewedAssetIDs.contains(assetID) == true { return }
                
                results.append(asset)
                if let resources = PHAssetResource.assetResources(for: asset).first,
                   let size = resources.value(forKey: "fileSize") as? Int64 {
                    totalSize += size
                }
                if results.count >= limit {
                    stop.pointee = true
                }
            }
            
            return (results, totalSize)
        }.value
    }
    
    // MARK: - Documents/Notes Detection (Screenshots with text-like characteristics)
    
    /// Finds screenshots that look like documents or notes
    func findDocuments(limit: Int = 50, limitMultiplier: Int = 1) async -> (assets: [PHAsset], totalSize: Int64) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return ([], 0)
        }
        
        return await Task.detached(priority: .userInitiated) { [self] in
            var results: [PHAsset] = []
            var totalSize: Int64 = 0
            
            // Find screenshots (many are document/text captures)
            let options = PHFetchOptions()
            options.predicate = NSPredicate(
                format: "(mediaSubtypes & %d) != 0",
                PHAssetMediaSubtype.photoScreenshot.rawValue
            )
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            
            let screenshots = PHAsset.fetchAssets(with: .image, options: options)
            
            let scanLimit = 1000 * limitMultiplier
            screenshots.enumerateObjects { asset, index, stop in
                if index >= scanLimit {
                    stop.pointee = true
                    return
                }
                
                if self.cachedStats?.reviewedAssetIDs.contains(asset.localIdentifier) == true { return }
                if let resources = PHAssetResource.assetResources(for: asset).first,
                   let size = resources.value(forKey: "fileSize") as? Int64 {
                    totalSize += size
                }
                if results.count >= limit {
                    stop.pointee = true
                }
            }
            
            return (results, totalSize)
        }.value
    }
    
    // MARK: - Similar Photos Detection
    
    /// Finds photos taken within 2 seconds of each other (burst-like behavior)
    func findSimilarPhotos(limit: Int = 50, limitMultiplier: Int = 1) async -> (assets: [PHAsset], totalSize: Int64) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return ([], 0)
        }
        
        return await Task.detached(priority: .userInitiated) { [self] in
            var results: [PHAsset] = []
            var totalSize: Int64 = 0
            
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let photos = PHAsset.fetchAssets(with: .image, options: options)
            
            var previousAsset: PHAsset?
            var previousDate: Date?
            var clusteredAssets: [[PHAsset]] = []
            var currentCluster: [PHAsset] = []
            
            let scanLimit = 2000 * limitMultiplier
            photos.enumerateObjects { asset, index, stop in
                if index >= scanLimit {
                    stop.pointee = true
                    return
                }
                
                guard let creationDate = asset.creationDate else { return }
                
                if let prevDate = previousDate, let prevAsset = previousAsset {
                    let timeDiff = creationDate.timeIntervalSince(prevDate)
                    
                    // If photos are within 2 seconds, they're similar
                    if timeDiff <= 2.0 && timeDiff >= 0 {
                        if currentCluster.isEmpty {
                            currentCluster.append(prevAsset)
                        }
                        currentCluster.append(asset)
                    } else if !currentCluster.isEmpty {
                        if currentCluster.count >= 2 {
                            clusteredAssets.append(currentCluster)
                        }
                        currentCluster = []
                    }
                }
                
                previousAsset = asset
                previousDate = creationDate
                
                // Limit processing for performance
                if clusteredAssets.count >= limit / 2 {
                    stop.pointee = true
                }
            }
            
            // Add last cluster if valid
            if currentCluster.count >= 2 {
                clusteredAssets.append(currentCluster)
            }
            
            // Flatten and calculate size (skip the first photo in each cluster - that's the "keeper")
            for cluster in clusteredAssets {
                for asset in cluster.dropFirst() {
                    if self.cachedStats?.reviewedAssetIDs.contains(asset.localIdentifier) == true { continue }
                    
                    results.append(asset)
                    if let resources = PHAssetResource.assetResources(for: asset).first,
                       let size = resources.value(forKey: "fileSize") as? Int64 {
                        totalSize += size
                    }
                    if results.count >= limit {
                        break
                    }
                }
                if results.count >= limit {
                    break
                }
            }
            
            return (results, totalSize)
        }.value
    }
    
    // MARK: - Old Screenshots Detection
    
    /// Finds screenshots older than the specified number of months
    func findOldScreenshots(olderThanMonths: Int = 6, limit: Int = 100, limitMultiplier: Int = 1) async -> (assets: [PHAsset], totalSize: Int64) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return ([], 0)
        }
        
        return await Task.detached(priority: .userInitiated) { [self] in
            var results: [PHAsset] = []
            var totalSize: Int64 = 0
            
            let cutoffDate = Calendar.current.date(byAdding: .month, value: -olderThanMonths, to: Date()) ?? Date()
            
            let options = PHFetchOptions()
            options.predicate = NSPredicate(
                format: "(mediaSubtypes & %d) != 0 AND creationDate < %@",
                PHAssetMediaSubtype.photoScreenshot.rawValue,
                cutoffDate as NSDate
            )
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            
            let screenshots = PHAsset.fetchAssets(with: .image, options: options)
            
            screenshots.enumerateObjects { asset, _, stop in
                if self.cachedStats?.reviewedAssetIDs.contains(asset.localIdentifier) == true { return }
                
                results.append(asset)
                if let resources = PHAssetResource.assetResources(for: asset).first,
                   let size = resources.value(forKey: "fileSize") as? Int64 {
                    totalSize += size
                }
                if results.count >= limit {
                    stop.pointee = true
                }
            }
            
            return (results, totalSize)
        }.value
    }
    
    // MARK: - Large Videos Detection (100MB+)
    
    /// Finds videos larger than the specified threshold (default 100MB)
    func findLargeVideos(threshold: Int64 = 100 * 1024 * 1024, limit: Int = 50, limitMultiplier: Int = 1) async -> (assets: [PHAsset], totalSize: Int64) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return ([], 0)
        }
        
        return await Task.detached(priority: .userInitiated) { [self] in
            var results: [(asset: PHAsset, size: Int64)] = []
            
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let videos = PHAsset.fetchAssets(with: .video, options: options)
            
            let scanLimit = 1000 * limitMultiplier
            videos.enumerateObjects { asset, index, stop in
                if index >= scanLimit {
                    stop.pointee = true
                    return
                }
                
                if self.cachedStats?.reviewedAssetIDs.contains(asset.localIdentifier) == true { return }
                
                if let resources = PHAssetResource.assetResources(for: asset).first {
                    if let size = resources.value(forKey: "fileSize") as? Int64, size >= threshold {
                        results.append((asset, size))
                    }
                }
                if results.count >= limit * 2 {
                    stop.pointee = true
                }
            }
            
            // Sort by size descending
            results.sort { $0.size > $1.size }
            let topResults = Array(results.prefix(limit))
            let totalSize = topResults.reduce(0) { $0 + $1.size }
            
            return (topResults.map { $0.asset }, totalSize)
        }.value
    }
    
    // MARK: - Live Photos Detection
    
    /// Finds Live Photos in the library
    func findLivePhotos(limit: Int = 100, limitMultiplier: Int = 1) async -> (assets: [PHAsset], totalSize: Int64) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return ([], 0)
        }
        
        return await Task.detached(priority: .userInitiated) { [self] in
            var results: [PHAsset] = []
            var totalSize: Int64 = 0
            
            let options = PHFetchOptions()
            options.predicate = NSPredicate(
                format: "(mediaSubtypes & %d) != 0",
                PHAssetMediaSubtype.photoLive.rawValue
            )
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            
            let livePhotos = PHAsset.fetchAssets(with: .image, options: options)
            
            let scanLimit = 1000 * limitMultiplier
            livePhotos.enumerateObjects { asset, index, stop in
                if index >= scanLimit {
                    stop.pointee = true
                    return
                }
                
                if self.cachedStats?.reviewedAssetIDs.contains(asset.localIdentifier) == true { return }
                
                results.append(asset)
                // Calculate total size including video component
                let resources = PHAssetResource.assetResources(for: asset)
                for resource in resources {
                    if let size = resource.value(forKey: "fileSize") as? Int64 {
                        totalSize += size
                    }
                }
                if results.count >= limit {
                    stop.pointee = true
                }
            }
            
            return (results, totalSize)
        }.value
    }
    
    // MARK: - Saved/Downloaded Images Detection
    
    /// Finds images that were saved/downloaded rather than taken with camera
    func findSavedImages(limit: Int = 100, limitMultiplier: Int = 1) async -> (assets: [PHAsset], totalSize: Int64) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return ([], 0)
        }
        
        return await Task.detached(priority: .userInitiated) { [self] in
            var results: [PHAsset] = []
            var totalSize: Int64 = 0
            
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let images = PHAsset.fetchAssets(with: .image, options: options)
            
            let scanLimit = 2000 * limitMultiplier
            images.enumerateObjects { asset, index, stop in
                if index >= scanLimit {
                    stop.pointee = true
                    return
                }
                
                if self.cachedStats?.reviewedAssetIDs.contains(asset.localIdentifier) == true { return }
                
                // Heuristics for saved/downloaded images:
                // 1. No location data
                // 2. Not a screenshot
                // 3. Not a Live Photo
                let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
                let isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
                let hasLocation = asset.location != nil
                
                if !isScreenshot && !isLivePhoto && !hasLocation {
                    results.append(asset)
                    if let resources = PHAssetResource.assetResources(for: asset).first,
                       let size = resources.value(forKey: "fileSize") as? Int64 {
                        totalSize += size
                    }
                }
                
                if results.count >= limit {
                    stop.pointee = true
                }
            }
            
            return (results, totalSize)
        }.value
    }
    
    // MARK: - Burst Photos Detection
    
    /// Finds burst photo groups and returns all non-representative photos
    func findBurstPhotos(limit: Int = 50, limitMultiplier: Int = 1) async -> (assets: [PHAsset], totalSize: Int64) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return ([], 0)
        }
        
        return await Task.detached(priority: .userInitiated) { [self] in
            var results: [PHAsset] = []
            var totalSize: Int64 = 0
            
            // Fetch burst assets (non-representative ones that can be deleted)
            let options = PHFetchOptions()
            options.predicate = NSPredicate(
                format: "burstIdentifier != nil"
            )
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.includeAllBurstAssets = true
            
            let burstPhotos = PHAsset.fetchAssets(with: .image, options: options)
            
            let scanLimit = 1000 * limitMultiplier
            burstPhotos.enumerateObjects { asset, index, stop in
                if index >= scanLimit {
                    stop.pointee = true
                    return
                }
                
                if self.cachedStats?.reviewedAssetIDs.contains(asset.localIdentifier) == true { return }
                
                // Filter here since representsBurst is not supported in fetch predicate
                if !asset.representsBurst {
                    results.append(asset)
                    if let resources = PHAssetResource.assetResources(for: asset).first,
                       let size = resources.value(forKey: "fileSize") as? Int64 {
                        totalSize += size
                    }
                    if results.count >= limit {
                        stop.pointee = true
                    }
                }
            }
            
            return (results, totalSize)
        }.value
    }
    
    // MARK: - Duplicates Detection
    
    /// Finds duplicate images using Vision-based detection
    // MARK: - Storage Size Calculation
    
    /// Calculates total storage size for an array of assets
    func calculateTotalSize(for assets: [PHAsset]) async -> Int64 {
        return await Task.detached(priority: .utility) {
            var totalSize: Int64 = 0
            for asset in assets {
                if let resources = PHAssetResource.assetResources(for: asset).first,
                   let size = resources.value(forKey: "fileSize") as? Int64 {
                    totalSize += size
                }
            }
            return totalSize
        }.value
    }
    
    // MARK: - Load All Modes (Original)
    
    /// Loads the original cleaning modes with their storage sizes (for backward compatibility)
    func loadAllModes() async -> [SmartCleaningMode] {
        async let largeMedia = findLargeMedia(limitMultiplier: 1)
        async let screenRecordings = findScreenRecordings(limitMultiplier: 1)
        async let documents = findDocuments(limitMultiplier: 1)
        async let similarPhotos = findSimilarPhotos(limitMultiplier: 1)
        async let blurryPhotos = SmartAICleanupService.shared.findBlackScreensAndBlurryPhotos(scanMultiplier: 1)
        
        let largeMediaResult = await largeMedia
        let screenRecordingsResult = await screenRecordings
        let documentsResult = await documents
        let similarPhotosResult = await similarPhotos
        let blurryPhotosResult = await blurryPhotos
        let blurryPhotosSize = await calculateTotalSize(for: blurryPhotosResult)
        
        return [
            SmartCleaningMode(
                id: .largeMedia,
                title: CleaningModeType.largeMedia.title,
                subtitle: CleaningModeType.largeMedia.subtitle,
                icon: CleaningModeType.largeMedia.icon,
                color: CleaningModeType.largeMedia.colorName,
                assets: largeMediaResult.assets,
                totalSize: largeMediaResult.totalSize,
                isLoading: false
            ),
            SmartCleaningMode(
                id: .screenRecordings,
                title: CleaningModeType.screenRecordings.title,
                subtitle: CleaningModeType.screenRecordings.subtitle,
                icon: CleaningModeType.screenRecordings.icon,
                color: CleaningModeType.screenRecordings.colorName,
                assets: screenRecordingsResult.assets,
                totalSize: screenRecordingsResult.totalSize,
                isLoading: false
            ),
            SmartCleaningMode(
                id: .documents,
                title: CleaningModeType.documents.title,
                subtitle: CleaningModeType.documents.subtitle,
                icon: CleaningModeType.documents.icon,
                color: CleaningModeType.documents.colorName,
                assets: documentsResult.assets,
                totalSize: documentsResult.totalSize,
                isLoading: false
            ),
            SmartCleaningMode(
                id: .similarPhotos,
                title: CleaningModeType.similarPhotos.title,
                subtitle: CleaningModeType.similarPhotos.subtitle,
                icon: CleaningModeType.similarPhotos.icon,
                color: CleaningModeType.similarPhotos.colorName,
                assets: similarPhotosResult.assets,
                totalSize: similarPhotosResult.totalSize,
                isLoading: false
            ),
            SmartCleaningMode(
                id: .blurryPhotos,
                title: CleaningModeType.blurryPhotos.title,
                subtitle: CleaningModeType.blurryPhotos.subtitle,
                icon: CleaningModeType.blurryPhotos.icon,
                color: CleaningModeType.blurryPhotos.colorName,
                assets: blurryPhotosResult,
                totalSize: blurryPhotosSize,
                isLoading: false
            ),
        ]
    }
    
    // MARK: - Load Hub Modes (Quick Wins + Deep Clean)
    
    /// Loads all hub modes organized by Quick Wins and Deep Clean
    /// - Parameter limitMultiplier: Factor to increase the default search limits
    func loadHubModes(limitMultiplier: Int = 1) async -> [SmartCleaningMode] {
        // Quick Wins
        async let largeVideos = findLargeVideos(limit: 50 * limitMultiplier, limitMultiplier: limitMultiplier)
        async let blurryPhotos = SmartAICleanupService.shared.findBlackScreensAndBlurryPhotos(scanMultiplier: limitMultiplier)
        async let oldScreenshots = findOldScreenshots(limit: 100 * limitMultiplier, limitMultiplier: limitMultiplier)
        async let screenRecordings = findScreenRecordings(limit: 50 * limitMultiplier, limitMultiplier: limitMultiplier)
        
        // Deep Clean
        async let similarPhotos = findSimilarPhotos(limit: 50 * limitMultiplier, limitMultiplier: limitMultiplier)
        async let livePhotos = findLivePhotos(limit: 100 * limitMultiplier, limitMultiplier: limitMultiplier)
        async let savedImages = findSavedImages(limit: 100 * limitMultiplier, limitMultiplier: limitMultiplier)
        async let burstPhotos = findBurstPhotos(limit: 50 * limitMultiplier, limitMultiplier: limitMultiplier)
        
        let largeVideosResult = await largeVideos
        let blurryPhotosResult = await blurryPhotos
        let blurryPhotosSize = await calculateTotalSize(for: blurryPhotosResult)
        let oldScreenshotsResult = await oldScreenshots
        let screenRecordingsResult = await screenRecordings
        let similarPhotosResult = await similarPhotos
        let livePhotosResult = await livePhotos
        let savedImagesResult = await savedImages
        let burstPhotosResult = await burstPhotos
        
        return [
            // Quick Wins
            SmartCleaningMode(
                id: .largeVideos,
                title: CleaningModeType.largeVideos.title,
                subtitle: CleaningModeType.largeVideos.subtitle,
                icon: CleaningModeType.largeVideos.icon,
                color: CleaningModeType.largeVideos.colorName,
                assets: largeVideosResult.assets,
                totalSize: largeVideosResult.totalSize,
                isLoading: false
            ),
            SmartCleaningMode(
                id: .blurryPhotos,
                title: CleaningModeType.blurryPhotos.title,
                subtitle: CleaningModeType.blurryPhotos.subtitle,
                icon: CleaningModeType.blurryPhotos.icon,
                color: CleaningModeType.blurryPhotos.colorName,
                assets: blurryPhotosResult,
                totalSize: blurryPhotosSize,
                isLoading: false
            ),
            SmartCleaningMode(
                id: .oldScreenshots,
                title: CleaningModeType.oldScreenshots.title,
                subtitle: CleaningModeType.oldScreenshots.subtitle,
                icon: CleaningModeType.oldScreenshots.icon,
                color: CleaningModeType.oldScreenshots.colorName,
                assets: oldScreenshotsResult.assets,
                totalSize: oldScreenshotsResult.totalSize,
                isLoading: false
            ),
            SmartCleaningMode(
                id: .screenRecordings,
                title: CleaningModeType.screenRecordings.title,
                subtitle: CleaningModeType.screenRecordings.subtitle,
                icon: CleaningModeType.screenRecordings.icon,
                color: CleaningModeType.screenRecordings.colorName,
                assets: screenRecordingsResult.assets,
                totalSize: screenRecordingsResult.totalSize,
                isLoading: false
            ),
            // Deep Clean
            SmartCleaningMode(
                id: .similarPhotos,
                title: CleaningModeType.similarPhotos.title,
                subtitle: CleaningModeType.similarPhotos.subtitle,
                icon: CleaningModeType.similarPhotos.icon,
                color: CleaningModeType.similarPhotos.colorName,
                assets: similarPhotosResult.assets,
                totalSize: similarPhotosResult.totalSize,
                isLoading: false
            ),
            SmartCleaningMode(
                id: .livePhotos,
                title: CleaningModeType.livePhotos.title,
                subtitle: CleaningModeType.livePhotos.subtitle,
                icon: CleaningModeType.livePhotos.icon,
                color: CleaningModeType.livePhotos.colorName,
                assets: livePhotosResult.assets,
                totalSize: livePhotosResult.totalSize,
                isLoading: false
            ),
            SmartCleaningMode(
                id: .savedImages,
                title: CleaningModeType.savedImages.title,
                subtitle: CleaningModeType.savedImages.subtitle,
                icon: CleaningModeType.savedImages.icon,
                color: CleaningModeType.savedImages.colorName,
                assets: savedImagesResult.assets,
                totalSize: savedImagesResult.totalSize,
                isLoading: false
            ),
            SmartCleaningMode(
                id: .burstPhotos,
                title: CleaningModeType.burstPhotos.title,
                subtitle: CleaningModeType.burstPhotos.subtitle,
                icon: CleaningModeType.burstPhotos.icon,
                color: CleaningModeType.burstPhotos.colorName,
                assets: burstPhotosResult.assets,
                totalSize: burstPhotosResult.totalSize,
                isLoading: false
            )
        ]
    }
    
    // MARK: - Cache Management
    
    /// Load cached stats from UserDefaults
    private func loadCachedStats() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode(SmartCleanupCache.self, from: data) else {
            cachedStats = SmartCleanupCache()
            return
        }
        cachedStats = cache
    }
    
    /// Save cache stats to UserDefaults
    private func saveCacheStats(_ modes: [SmartCleaningMode]) {
        var cache = SmartCleanupCache()
        cache.lastScanTimestamp = Date()
        
        for mode in modes {
            cache.modeStats[mode.id.rawValue] = SmartCleanupCache.ModeStats(
                assetCount: mode.assetCount,
                totalSize: mode.totalSize,
                assetIdentifiers: mode.assets.map { $0.localIdentifier }
            )
            // Also update in-memory cache
            cachedAssets[mode.id] = mode.assets
        }
        
        cachedStats = cache
        
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
    
    /// Load hub modes with caching - returns cached data instantly if available
    /// - Parameters:
    ///   - forceRefresh: If true, ignores cache and does fresh scan
    ///   - limitMultiplier: Factor to increase the default search limits when refreshing
    /// - Returns: Array of SmartCleaningMode with cached or fresh data
    func loadHubModesCached(forceRefresh: Bool = false, limitMultiplier: Int = 1) async -> [SmartCleaningMode] {
        // If we have valid cache and don't need refresh or expansion, return cached immediately
        if !forceRefresh && limitMultiplier == 1, let cache = cachedStats, cache.isValid {
            // Build modes from cached stats
            let cachedModes = buildModesFromCache(cache)
            if !cachedModes.isEmpty {
                return cachedModes
            }
        }
        
        // Otherwise do a fresh load and cache results
        let modes = await loadHubModes(limitMultiplier: limitMultiplier)
        saveCacheStats(modes)
        return modes
    }
    
    /// Marks an array of assets as reviewed so they won't appear in future smart scans
    func markAsReviewed(assets: [PHAsset]) {
        if cachedStats == nil {
            loadCachedStats()
        }
        
        let identifiers = assets.map { $0.localIdentifier }
        cachedStats?.reviewedAssetIDs.formUnion(identifiers)
        
        if let cache = cachedStats, let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
        
        // Clear in-memory cache to force re-fetch without reviewed items
        cachedAssets.removeAll()
    }
    
    /// Updates the cache after a successful deletion to reflect subtraction without a full re-scan
    func updateCacheAfterDeletion(assets: [PHAsset], modeID: CleaningModeType) {
        if cachedStats == nil {
            loadCachedStats()
        }
        
        guard var stats = cachedStats?.modeStats[modeID.rawValue] else { return }
        
        let deletedIDs = Set(assets.map { $0.localIdentifier })
        let remainingIDs = stats.assetIdentifiers.filter { !deletedIDs.contains($0) }
        
        // Calculate total size of deleted assets
        var deletedSize: Int64 = 0
        for asset in assets {
            if let resources = PHAssetResource.assetResources(for: asset).first,
               let size = resources.value(forKey: "fileSize") as? Int64 {
                deletedSize += size
            }
        }
        
        // Update stats
        let newStats = SmartCleanupCache.ModeStats(
            assetCount: remainingIDs.count,
            totalSize: max(0, stats.totalSize - deletedSize),
            assetIdentifiers: remainingIDs
        )
        
        cachedStats?.modeStats[modeID.rawValue] = newStats
        
        // Update persisted cache
        if let cache = cachedStats, let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
        
        // Update in-memory assets if they exist
        if var cached = cachedAssets[modeID] {
            cached.removeAll(where: { deletedIDs.contains($0.localIdentifier) })
            cachedAssets[modeID] = cached
        }
    }
    
    /// Clears all reviewed assets, allowing them to appear in scans again
    func clearReviewedAssets() {
        cachedStats?.reviewedAssetIDs.removeAll()
        
        if let cache = cachedStats, let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
        
        cachedAssets.removeAll()
    }
    
    /// Build SmartCleaningMode array from cache (without actual assets loaded yet)
    private func buildModesFromCache(_ cache: SmartCleanupCache) -> [SmartCleaningMode] {
        // Define the order of modes to match loadHubModes
        let modeTypes: [CleaningModeType] = [
            .largeVideos, .blurryPhotos, .oldScreenshots, .screenRecordings,
            .similarPhotos, .livePhotos, .savedImages, .burstPhotos
        ]
        
        return modeTypes.compactMap { modeType in
            guard let stats = cache.modeStats[modeType.rawValue] else {
                return nil
            }
            
            // Try to get assets from in-memory cache, or fetch from identifiers
            let assets: [PHAsset]
            if let cached = cachedAssets[modeType], !cached.isEmpty {
                assets = cached
            } else if !stats.assetIdentifiers.isEmpty {
                // Fetch assets from identifiers (this is fast since Photos framework caches)
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: stats.assetIdentifiers, options: nil)
                var fetchedAssets: [PHAsset] = []
                fetchResult.enumerateObjects { asset, _, _ in
                    fetchedAssets.append(asset)
                }
                assets = fetchedAssets
                cachedAssets[modeType] = assets
            } else {
                assets = []
            }
            
            let filteredAssets = assets.filter { !cache.reviewedAssetIDs.contains($0.localIdentifier) }
            
            return SmartCleaningMode(
                id: modeType,
                title: modeType.title,
                subtitle: modeType.subtitle,
                icon: modeType.icon,
                color: modeType.colorName,
                assets: filteredAssets,
                totalSize: stats.totalSize, // Note: Size might be slightly off until next refresh
                isLoading: false
            )
        }
    }
    
    /// Preload hub modes in background during app launch
    /// This runs at low priority to not impact UI performance
    func preloadHubModesInBackground() {
        guard !isPreloading else { return }
        
        // Check if we already have valid cache
        if let cache = cachedStats, cache.isValid {
            return // Already have fresh data
        }
        
        isPreloading = true
        
        Task(priority: .background) { [weak self] in
            guard let self = self else { return }
            
            // Wait a bit to let the app fully launch first
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            let modes = await self.loadHubModes()
            self.saveCacheStats(modes)
            self.isPreloading = false
        }
    }
    
    /// Invalidate cache - call after deletions to ensure fresh data on next load
    func invalidateCache() {
        cachedStats = nil
        cachedAssets.removeAll()
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
    
    /// Check if cache has valid data
    var hasCachedData: Bool {
        cachedStats?.isValid == true && !(cachedStats?.modeStats.isEmpty ?? true)
    }
}
