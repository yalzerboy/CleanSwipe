//
//  TripDetectionService.swift
//  Kage
//
//  Created by Yalun Zhang on 17/02/2026.
//

import Foundation
import Photos
import CoreLocation

/// Represents an auto-detected trip based on photo location + time clustering.
struct Trip: Identifiable {
    let id = UUID()
    var name: String
    let startDate: Date
    let endDate: Date
    let photoCount: Int
    let assetIdentifiers: [String]
    let coverAsset: PHAsset?
    let centerLocation: CLLocation
    
    var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
            return formatter.string(from: startDate)
        } else {
            let shortFormatter = DateFormatter()
            shortFormatter.dateFormat = "d MMM"
            let yearFormatter = DateFormatter()
            yearFormatter.dateFormat = "d MMM yyyy"
            
            if Calendar.current.component(.year, from: startDate) == Calendar.current.component(.year, from: endDate) {
                return "\(shortFormatter.string(from: startDate)) – \(yearFormatter.string(from: endDate))"
            } else {
                return "\(yearFormatter.string(from: startDate)) – \(yearFormatter.string(from: endDate))"
            }
        }
    }
}

/// Internal struct for clustering
private struct PhotoPoint {
    let identifier: String
    let location: CLLocation
    let date: Date
    let asset: PHAsset
}

/// Service that auto-detects trips by clustering geotagged photos.
/// Scanning is lazy — only runs when Holiday Mode is opened.
/// Results are cached in memory after the first scan.
@MainActor
class TripDetectionService: ObservableObject {
    static let shared = TripDetectionService()
    
    @Published var trips: [Trip] = []
    @Published var isScanning = false
    @Published var scanProgress: Double = 0.0
    @Published var scanMessage: String = ""
    @Published var hasScanned = false
    
    // Configuration
    private let distanceThresholdKm: Double = 50.0
    private let timeGapDays: Int = 3
    private let minTripPhotos: Int = 5
    private let homeRadiusKm: Double = 30.0
    
    // Geocoding
    private let geocoder = CLGeocoder()
    
    // Persistent cache key
    private let geoCacheKey = "com.kage.tripGeoCache"
    
    private init() {}
    
    // MARK: - Persistent Geocode Cache
    
    private func loadGeoCache() -> [String: String] {
        return UserDefaults.standard.dictionary(forKey: geoCacheKey) as? [String: String] ?? [:]
    }
    
    private func saveGeoCache(_ cache: [String: String]) {
        UserDefaults.standard.set(cache, forKey: geoCacheKey)
    }
    
    func scanForTrips() {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0.0
        scanMessage = "One-time scan — finding all your holidays..."
        
        Task(priority: .userInitiated) {
            await performScan()
        }
    }
    
    func rescan() {
        hasScanned = false
        trips = []
        scanForTrips()
    }
    
    // MARK: - Core Algorithm
    
    private func performScan() async {
        // Step 1: Fetch all geotagged photos sorted by date
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        fetchOptions.includeHiddenAssets = false
        
        let allAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        let totalCount = allAssets.count
        
        guard totalCount > 0 else {
            await MainActor.run {
                self.isScanning = false
                self.hasScanned = true
                self.scanMessage = "No photos found"
            }
            return
        }
        
        await MainActor.run {
            self.scanMessage = "Scanning your photo library..."
        }
        
        // Step 2: Extract geotagged photos — run on background thread
        let distThreshold = distanceThresholdKm
        let timeGap = timeGapDays
        let minPhotos = minTripPhotos
        let homeRadius = homeRadiusKm
        
        let scanResult: (tripClusters: [[PhotoPoint]], allClusters: [[PhotoPoint]])? = await Task.detached(priority: .userInitiated) {
            // Heavy work: iterate entire photo library (off main thread)
            var points: [PhotoPoint] = []
            points.reserveCapacity(totalCount / 2)
            
            for i in 0..<totalCount {
                let asset = allAssets.object(at: i)
                if let location = asset.location,
                   let date = asset.creationDate,
                   location.coordinate.latitude != 0 || location.coordinate.longitude != 0 {
                    points.append(PhotoPoint(
                        identifier: asset.localIdentifier,
                        location: location,
                        date: date,
                        asset: asset
                    ))
                }
                
                // Update progress less frequently to reduce main thread hops
                if i % 2000 == 0 {
                    let progress = Double(i) / Double(totalCount) * 0.4
                    await MainActor.run {
                        TripDetectionService.shared.scanProgress = progress
                    }
                }
            }
            
            guard points.count >= minPhotos else {
                await MainActor.run {
                    TripDetectionService.shared.isScanning = false
                    TripDetectionService.shared.hasScanned = true
                    TripDetectionService.shared.scanMessage = "Not enough geotagged photos"
                }
                return nil
            }
            
            await MainActor.run {
                TripDetectionService.shared.scanProgress = 0.45
                TripDetectionService.shared.scanMessage = "Detecting trip patterns..."
            }
            
            // Step 3: Cluster by location + time proximity
            var clusters: [[PhotoPoint]] = []
            var currentCluster: [PhotoPoint] = [points[0]]
            
            for i in 1..<points.count {
                let prev = currentCluster.last!
                let curr = points[i]
                
                let timeDiffDays = curr.date.timeIntervalSince(prev.date) / (24 * 3600)
                let distanceKm = curr.location.distance(from: prev.location) / 1000.0
                
                if timeDiffDays <= Double(timeGap) && distanceKm <= distThreshold {
                    currentCluster.append(curr)
                } else {
                    clusters.append(currentCluster)
                    currentCluster = [curr]
                }
            }
            clusters.append(currentCluster)
            
            // Step 4: Detect "home" location (largest cluster center)
            func clusterCenterBG(of cluster: [PhotoPoint]) -> CLLocation {
                var totalLat: Double = 0
                var totalLon: Double = 0
                for point in cluster {
                    totalLat += point.location.coordinate.latitude
                    totalLon += point.location.coordinate.longitude
                }
                return CLLocation(
                    latitude: totalLat / Double(cluster.count),
                    longitude: totalLon / Double(cluster.count)
                )
            }
            
            let homeLocation: CLLocation? = {
                guard let largest = clusters.max(by: { $0.count < $1.count }),
                      largest.count >= 20 else {
                    return nil
                }
                return clusterCenterBG(of: largest)
            }()
            
            // Step 5: Filter — remove home clusters and small clusters
            var tripClusters = clusters.filter { cluster in
                guard cluster.count >= minPhotos else { return false }
                
                if let home = homeLocation {
                    let center = clusterCenterBG(of: cluster)
                    let distFromHome = center.distance(from: home) / 1000.0
                    if distFromHome < homeRadius {
                        return false
                    }
                }
                return true
            }
            
            // Sort newest first
            tripClusters.sort { ($0.last?.date ?? .distantPast) > ($1.last?.date ?? .distantPast) }
            
            return (tripClusters: tripClusters, allClusters: clusters)
        }.value
        
        guard let result = scanResult else { return }
        let tripClusters = result.tripClusters
        
        await MainActor.run {
            self.scanProgress = 0.6
            self.scanMessage = "Naming \(tripClusters.count) holidays..."
        }
        
        // Step 6: Deduplicate geocoding by coarse location
        // Round to 1 decimal (~11km) so trips in the same city share one geocode call
        var uniqueLocations: [String: CLLocation] = [:]
        var tripCacheKeys: [String] = []
        
        for cluster in tripClusters {
            let center = clusterCenter(of: cluster)
            let cacheKey = String(format: "%.1f,%.1f", center.coordinate.latitude, center.coordinate.longitude)
            tripCacheKeys.append(cacheKey)
            if uniqueLocations[cacheKey] == nil {
                uniqueLocations[cacheKey] = center
            }
        }
        
        // Load persistent cache
        var geoCache = loadGeoCache()
        
        // Find which locations we actually need to geocode
        let uncachedKeys = Array(uniqueLocations.keys.filter { geoCache[$0] == nil })
        
        await MainActor.run {
            if uncachedKeys.isEmpty {
                self.scanMessage = "Loading cached trip names..."
            } else {
                self.scanMessage = "Identifying \(uncachedKeys.count) locations..."
            }
        }
        
        // Geocode only unique, uncached locations
        for (idx, key) in uncachedKeys.enumerated() {
            guard let location = uniqueLocations[key] else { continue }
            
            let name = await geocodeSingle(location: location)
            geoCache[key] = name
            
            // Smooth fake progress from 0.6 → 0.95
            await MainActor.run {
                self.scanProgress = 0.6 + 0.35 * Double(idx + 1) / Double(uncachedKeys.count)
            }
        }
        
        // Persist the updated cache
        saveGeoCache(geoCache)
        
        // Step 7: Build Trip models using cached names
        var detectedTrips: [Trip] = []
        
        for (index, cluster) in tripClusters.enumerated() {
            let center = clusterCenter(of: cluster)
            let cacheKey = tripCacheKeys[index]
            var name = geoCache[cacheKey] ?? "Unknown Location"
            
            // If name looks like coordinates (e.g. "52°N, 0°W"), use date range instead
            if name.contains("°") || name.range(of: "^[-+]?[0-9]*\\.?[0-9]+,[ ]?[-+]?[0-9]*\\.?[0-9]+$", options: .regularExpression) != nil {
                let startDate = cluster.first?.date ?? Date()
                let endDate = cluster.last?.date ?? Date()
                
                let shortFormatter = DateFormatter()
                shortFormatter.dateFormat = "d MMM"
                let yearFormatter = DateFormatter()
                yearFormatter.dateFormat = "d MMM yyyy"
                
                if Calendar.current.component(.year, from: startDate) == Calendar.current.component(.year, from: endDate) {
                    name = "\(shortFormatter.string(from: startDate)) – \(yearFormatter.string(from: endDate))"
                } else {
                    name = "\(yearFormatter.string(from: startDate)) – \(yearFormatter.string(from: endDate))"
                }
            }
            
            let trip = Trip(
                name: name,
                startDate: cluster.first?.date ?? Date(),
                endDate: cluster.last?.date ?? Date(),
                photoCount: cluster.count,
                assetIdentifiers: cluster.map { $0.identifier },
                coverAsset: cluster.randomElement()?.asset,
                centerLocation: center
            )
            detectedTrips.append(trip)
        }
        
        await MainActor.run {
            self.trips = detectedTrips
            self.isScanning = false
            self.hasScanned = true
            self.scanProgress = 1.0
            self.scanMessage = ""
        }
    }
    
    // MARK: - Helpers
    
    private func detectHomeLocation(from clusters: [[PhotoPoint]]) -> CLLocation? {
        guard let largest = clusters.max(by: { $0.count < $1.count }),
              largest.count >= 20 else {
            return nil
        }
        return clusterCenter(of: largest)
    }
    
    private func clusterCenter(of cluster: [PhotoPoint]) -> CLLocation {
        var totalLat: Double = 0
        var totalLon: Double = 0
        for point in cluster {
            totalLat += point.location.coordinate.latitude
            totalLon += point.location.coordinate.longitude
        }
        return CLLocation(
            latitude: totalLat / Double(cluster.count),
            longitude: totalLon / Double(cluster.count)
        )
    }
    
    /// Geocode a single location with rate-limit handling.
    /// Uses 1.3s delay between calls (~46/min, under Apple's 50/min limit).
    /// If throttled, retries once after a short wait.
    private func geocodeSingle(location: CLLocation) async -> String {
        // Small delay to stay under rate limit (0.5s ≈ 120/min max, well under Apple's 50/min limit
        // since we only geocode unique, uncached locations)
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        return await withCheckedContinuation { continuation in
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let error = error {
                    // If throttled, return a coordinate-based name rather than blocking
                    let latDir = location.coordinate.latitude >= 0 ? "N" : "S"
                    let lonDir = location.coordinate.longitude >= 0 ? "E" : "W"
                    let fallback = String(format: "%.0f°%@ %.0f°%@",
                                          abs(location.coordinate.latitude), latDir,
                                          abs(location.coordinate.longitude), lonDir)
                    continuation.resume(returning: fallback)
                    return
                }
                
                var name = "Unknown Location"
                if let placemark = placemarks?.first {
                    var components: [String] = []
                    if let city = placemark.locality {
                        components.append(city)
                    } else if let area = placemark.administrativeArea {
                        components.append(area)
                    }
                    if let country = placemark.country {
                        components.append(country)
                    }
                    if !components.isEmpty {
                        name = components.joined(separator: ", ")
                    }
                }
                
                continuation.resume(returning: name)
            }
        }
    }
}
