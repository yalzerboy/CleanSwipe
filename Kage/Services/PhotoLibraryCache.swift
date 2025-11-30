//
//  PhotoLibraryCache.swift
//  Kage
//
//  Created by AI Assistant on 08/11/2025.
//

import Photos
import UIKit

final class PhotoLibraryCache: @unchecked Sendable {
    static let shared = PhotoLibraryCache()

    private let cachingManager: PHCachingImageManager
    private let imageRequestOptions: PHImageRequestOptions
    private let metadataQueue = DispatchQueue(label: "com.yalun.CleanSwipe.photoMetadata", qos: .utility)
    private let resourceMetadataQueue = DispatchQueue(label: "com.yalun.CleanSwipe.photoResourceMetadata", qos: .utility)
    private let fileSizeCache = NSCache<NSString, NSNumber>()
    private var _fileSizeCacheCount = 0
    
    private init() {
        self.cachingManager = PHCachingImageManager()
        self.cachingManager.allowsCachingHighQualityImages = false

        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true
        self.imageRequestOptions = options

        // Set cache limits to prevent unbounded growth
        self.fileSizeCache.countLimit = 1000 // Limit to 1000 entries
    }

    // Debug property to check cache size
    var fileSizeCacheCount: Int {
        return _fileSizeCacheCount
    }

    func startCaching(assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty else { return }
        cachingManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: imageRequestOptions
        )
        
        // Warm up frequently accessed metadata off the main queue to avoid on-demand fetches later.
        metadataQueue.async {
            assets.forEach { asset in
                _ = asset.creationDate
                _ = asset.location
                _ = asset.pixelWidth
                _ = asset.pixelHeight
                if asset.mediaType == .video {
                    _ = asset.duration
                }
            }
            
            self.prefetchFileSizes(for: assets)
        }
    }
    
    func stopCaching(assets: [PHAsset], targetSize: CGSize) {
        guard !assets.isEmpty else { return }
        cachingManager.stopCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: imageRequestOptions
        )
    }
    
    func requestThumbnail(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            cachingManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: imageRequestOptions
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    func cachedFileSize(for asset: PHAsset) -> Int64? {
        fileSizeCache.object(forKey: asset.localIdentifier as NSString)?.int64Value
    }

    func fetchFileSize(for asset: PHAsset, completion: @escaping (Int64?) -> Void) {
        if let cached = cachedFileSize(for: asset) {
            DispatchQueue.main.async {
                completion(cached)
            }
            return
        }

        resourceMetadataQueue.async {
            let size = self.computeFileSize(for: asset)
            if let size = size {
                self.fileSizeCache.setObject(NSNumber(value: size), forKey: asset.localIdentifier as NSString)
                self._fileSizeCacheCount += 1
            }
            DispatchQueue.main.async {
                completion(size)
            }
        }
    }

    func fileSize(for asset: PHAsset) async -> Int64? {
        if let cached = cachedFileSize(for: asset) {
            return cached
        }

        return await withCheckedContinuation { continuation in
            resourceMetadataQueue.async {
                let size = self.computeFileSize(for: asset)
                if let size = size {
                    self.fileSizeCache.setObject(NSNumber(value: size), forKey: asset.localIdentifier as NSString)
                    self._fileSizeCacheCount += 1
                }
                continuation.resume(returning: size)
            }
        }
    }

    func prefetchFileSizes(for assets: [PHAsset]) {
        guard !assets.isEmpty else { return }

        resourceMetadataQueue.async {
            assets.forEach { asset in
                let assetID = asset.localIdentifier as NSString
                if self.fileSizeCache.object(forKey: assetID) != nil {
                    return
                }
                if let size = self.computeFileSize(for: asset) {
                    self.fileSizeCache.setObject(NSNumber(value: size), forKey: assetID)
                    self._fileSizeCacheCount += 1
                }
            }
        }
    }

    private func computeFileSize(for asset: PHAsset) -> Int64? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .photo || $0.type == .video }) ?? resources.first else {
            return nil
        }

        if let fileSize = resource.value(forKey: "fileSize") as? Int64 {
            return fileSize
        }

        if let number = resource.value(forKey: "fileSize") as? NSNumber {
            return number.int64Value
        }

        return nil
    }
}

