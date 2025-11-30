import Foundation
import Photos
import UIKit

final class SmartAICleanupService {
    static let shared = SmartAICleanupService()
    
    private let imageManager: PHCachingImageManager
    private let requestOptions: PHImageRequestOptions
    
    /// Maximum number of assets we will inspect before stopping.
    private let inspectionCap = 400
    
    private init() {
        self.imageManager = PHCachingImageManager()
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .exact
        options.isSynchronous = true
        options.isNetworkAccessAllowed = true
        self.requestOptions = options
    }
    
    /// Finds likely black-screen photos by sampling low-resolution thumbnails and
    /// measuring their average brightness.
    /// - Parameters:
    ///   - limit: Maximum number of assets to return.
    ///   - brightnessThreshold: Maximum average brightness (0...1) to consider a photo "black".
    /// - Returns: Array of `PHAsset` objects sorted by most recent first.
    func fetchBlackScreenCandidates(limit: Int = 40, brightnessThreshold: CGFloat = 0.08) async -> [PHAsset] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return []
        }
        
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false
        options.fetchLimit = inspectionCap
        
        let fetchedAssets = PHAsset.fetchAssets(with: .image, options: options)
        guard fetchedAssets.count > 0 else { return [] }
        
        var candidates: [PHAsset] = []
        let targetSize = CGSize(width: 32, height: 32)
        
        // Iterate synchronously for now since the thumbnails are tiny and capped.
        fetchedAssets.enumerateObjects { asset, _, stop in
            guard candidates.count < limit else {
                stop.pointee = true
                return
            }
            
            if let brightness = self.averageBrightness(for: asset, targetSize: targetSize),
               brightness <= brightnessThreshold {
                candidates.append(asset)
            }
        }
        
        return candidates
    }
    
    private func averageBrightness(for asset: PHAsset, targetSize: CGSize) -> CGFloat? {
        var resultImage: UIImage?
        self.imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: requestOptions) { image, _ in
            resultImage = image
        }
        
        guard let image = resultImage, let cgImage = image.cgImage else {
            return nil
        }
        
        guard let dataProvider = cgImage.dataProvider,
              let pixelData = dataProvider.data else {
            return nil
        }
        
        let data: Data = pixelData as Data
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        guard bytesPerPixel >= 3 else { return nil }
        
        var totalLuminance: CGFloat = 0
        let pixelCount = cgImage.width * cgImage.height
        
        data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            let pointer = baseAddress.bindMemory(to: UInt8.self, capacity: rawBuffer.count)
            
            for pixelIndex in 0..<pixelCount {
                let offset = pixelIndex * bytesPerPixel
                let r = CGFloat(pointer[offset])
                let g = CGFloat(pointer[offset + 1])
                let b = CGFloat(pointer[offset + 2])
                
                // Standard luminance calculation
                let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                totalLuminance += luminance / 255.0
            }
        }
        
        return totalLuminance / CGFloat(pixelCount)
    }
}


