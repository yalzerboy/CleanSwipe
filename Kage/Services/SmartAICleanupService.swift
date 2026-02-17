import Foundation
import Photos
import UIKit

final class SmartAICleanupService {
    static let shared = SmartAICleanupService()
    
    private let imageManager: PHCachingImageManager
    
    /// Very small thumbnail size for efficient analysis (32x32 is enough for brightness/blur detection)
    private let analysisThumbnailSize = CGSize(width: 32, height: 32)
    
    private init() {
        self.imageManager = PHCachingImageManager()
    }
    
    /// Finds black screens and completely blurry photos efficiently
    /// Searches current library and returns early after finding matches
    /// - Parameter scanMultiplier: Multiplier for the scan limit
    /// - Returns: Array of PHAsset objects sorted by most recent first (max 5)
    func findBlackScreensAndBlurryPhotos(scanMultiplier: Int = 1) async -> [PHAsset] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return []
        }
        
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false
        // No fetchLimit - search the whole library
        
        let fetchedAssets = PHAsset.fetchAssets(with: .image, options: options)
        guard fetchedAssets.count > 0 else { return [] }
        
        // Process in background to avoid blocking UI
        return await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return [] }
            var candidates: [PHAsset] = []
            
            // Process assets in batches to avoid memory pressure
            let batchSize = 20
            var processedCount = 0
            let earlyReturnLimit = 5 // Return after finding 5 matches
            let scanLimit = 1000 * scanMultiplier // Scan up to 1000 items (or more with multiplier)
            
            fetchedAssets.enumerateObjects { asset, index, stop in
                // Early return after finding 5 matches or reaching scan limit
                if candidates.count >= earlyReturnLimit || index >= scanLimit {
                    stop.pointee = true
                    return
                }
                
                // Process batch synchronously, then yield
                if self.isBlackScreenOrBlurry(asset) {
                    candidates.append(asset)
                }
                
                processedCount += 1
                if processedCount % batchSize == 0 {
                    // Yield to avoid blocking
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }
            
            return candidates
        }.value
    }
    
    /// Efficiently checks if a photo is a black screen or completely blurry
    func isBlackScreenOrBlurry(_ asset: PHAsset) -> Bool {
        // Use very small thumbnail and fast delivery for performance
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isSynchronous = true
        options.isNetworkAccessAllowed = false // Skip iCloud photos for performance
        
        var resultImage: UIImage?
        imageManager.requestImage(
            for: asset,
            targetSize: analysisThumbnailSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            resultImage = image
        }
        
        guard let image = resultImage, let cgImage = image.cgImage else {
            return false
        }
        
        // Check brightness first (faster check)
        if isBlackScreen(cgImage: cgImage) {
            return true
        }
        
        // Then check blur (slightly more expensive but still fast on 32x32 image)
        return isCompletelyBlurry(cgImage: cgImage)
    }
    
    /// Checks if image is a black screen using efficient pixel sampling
    private func isBlackScreen(cgImage: CGImage) -> Bool {
        // Sample pixels instead of reading all for better performance
        let width = cgImage.width
        let height = cgImage.height
        
        guard width > 0 && height > 0 else { return false }
        
        // Sample every 4th pixel in both dimensions (16x fewer samples)
        var totalBrightness: CGFloat = 0
        var sampleCount = 0
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return false
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Sample pixels (every 4th pixel for performance)
        for y in stride(from: 0, to: height, by: 4) {
            for x in stride(from: 0, to: width, by: 4) {
                let pixelIndex = (y * width + x) * bytesPerPixel
                guard pixelIndex + 2 < pixelData.count else { continue }
                
                let r = CGFloat(pixelData[pixelIndex])
                let g = CGFloat(pixelData[pixelIndex + 1])
                let b = CGFloat(pixelData[pixelIndex + 2])
                
                // Calculate luminance
                let luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                totalBrightness += luminance
                sampleCount += 1
            }
        }
        
        guard sampleCount > 0 else { return false }
        let averageBrightness = totalBrightness / CGFloat(sampleCount)
        
        // Black screen threshold (very dark images)
        return averageBrightness < 0.06
    }
    
    /// Checks if image is completely blurry using efficient edge detection
    private func isCompletelyBlurry(cgImage: CGImage) -> Bool {
        let width = cgImage.width
        let height = cgImage.height
        
        guard width > 2 && height > 2 else { return false }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return false
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Simple edge detection using Laplacian on sampled pixels
        var edgeStrengthSum: CGFloat = 0
        var sampleCount = 0
        
        // Sample center region and edges (skip border pixels)
        for y in 1..<(height-1) {
            for x in 1..<(width-1) {
                // Sample every 2nd pixel for better performance
                guard x % 2 == 0 && y % 2 == 0 else { continue }
                
                let centerIndex = (y * width + x) * bytesPerPixel
                let rightIndex = (y * width + (x + 1)) * bytesPerPixel
                let downIndex = ((y + 1) * width + x) * bytesPerPixel
                
                guard centerIndex + 2 < pixelData.count,
                      rightIndex + 2 < pixelData.count,
                      downIndex + 2 < pixelData.count else { continue }
                
                // Calculate luminance for edge detection
                let centerLum = luminance(
                    r: pixelData[centerIndex],
                    g: pixelData[centerIndex + 1],
                    b: pixelData[centerIndex + 2]
                )
                let rightLum = luminance(
                    r: pixelData[rightIndex],
                    g: pixelData[rightIndex + 1],
                    b: pixelData[rightIndex + 2]
                )
                let downLum = luminance(
                    r: pixelData[downIndex],
                    g: pixelData[downIndex + 1],
                    b: pixelData[downIndex + 2]
                )
                
                // Simple edge strength (Laplacian approximation)
                let edgeStrength = abs(centerLum - rightLum) + abs(centerLum - downLum)
                edgeStrengthSum += edgeStrength
                sampleCount += 1
            }
        }
        
        guard sampleCount > 0 else { return false }
        let averageEdgeStrength = edgeStrengthSum / CGFloat(sampleCount)
        
        // Very low edge strength indicates completely blurry image
        // Threshold tuned for 32x32 images (normalized)
        return averageEdgeStrength < 2.0
    }
    
    private func luminance(r: UInt8, g: UInt8, b: UInt8) -> CGFloat {
        return 0.299 * CGFloat(r) + 0.587 * CGFloat(g) + 0.114 * CGFloat(b)
    }
}


