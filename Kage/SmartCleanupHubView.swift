import SwiftUI
import Photos

/// Hub view for Smart AI Cleanup with Quick Wins and Deep Clean sections
struct SmartCleanupHubView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cleaningModes: [SmartCleaningMode] = []
    @State private var isLoading = true
    @State private var selectedMode: SmartCleaningMode?
    @State private var showingModeDetail = false
    @State private var limitMultiplier = 1
    @State private var isExpandingSearch = false
    
    let onDeletion: ((Int, [PHAsset]?, CleaningModeType?) -> Void)?
    
    init(onDeletion: ((Int, [PHAsset]?, CleaningModeType?) -> Void)? = nil) {
        self.onDeletion = onDeletion
    }
    
    // Separate modes by category
    private var quickWinsModes: [SmartCleaningMode] {
        cleaningModes.filter { $0.id.category == .quickWins }
    }
    
    private var deepCleanModes: [SmartCleaningMode] {
        cleaningModes.filter { $0.id.category == .deepClean }
    }
    
    // Calculate totals
    private var totalItems: Int {
        cleaningModes.reduce(0) { $0 + $1.assetCount }
    }
    
    private var totalSize: Int64 {
        cleaningModes.reduce(0) { $0 + $1.totalSize }
    }
    
    private var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    // Find the highest impact mode
    private var highestImpactMode: SmartCleaningMode? {
        cleaningModes.max(by: { $0.totalSize < $1.totalSize })
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if isLoading {
                    loadingView
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Header stats
                            headerSection
                            
                            // Quick Wins Section
                            if !quickWinsModes.isEmpty {
                                categorySection(
                                    title: "Quick Wins",
                                    subtitle: "Fast storage gains",
                                    icon: "bolt.fill",
                                    color: .orange,
                                    modes: quickWinsModes
                                )
                            }
                            
                            // Deep Clean Section
                            if !deepCleanModes.isEmpty {
                                categorySection(
                                    title: "Deep Clean",
                                    subtitle: "Thorough cleanup",
                                    icon: "sparkles",
                                    color: .purple,
                                    modes: deepCleanModes
                                )
                            }
                            
                            // Find More Button
                            findMoreButton
                        }
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("Smart Cleanup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await loadModes(forceRefresh: true)
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .disabled(isLoading)
                }
            }
        }
        .navigationViewStyle(.stack)
        .task {
            await loadModes()
        }
        .sheet(isPresented: $showingModeDetail) {
            if let mode = selectedMode {
                SmartCleaningDetailView(mode: mode, onDeletion: { count, deletedAssets, modeID in
                    onDeletion?(count, deletedAssets, modeID)
                    
                    // Update cache locally if we have the assets and mode
                    if let assets = deletedAssets, let mid = modeID {
                        SmartCleaningService.shared.updateCacheAfterDeletion(assets: assets, modeID: mid)
                    } else if count > 0 {
                        // Fallback: something was deleted but we don't know what, invalidate
                        SmartCleaningService.shared.invalidateCache()
                    }
                    
                    Task {
                        // Refresh from the updated cache (forceRefresh: false)
                        // This updates the Hub UI instantly without a full library scan
                        await loadModes(forceRefresh: false)
                    }
                })
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Scanning your library...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("Finding photos & videos to clean up")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Large storage indicator
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.purple)
                    
                    Text("Potential Savings")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                }
                
                Text(formattedTotalSize)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.purple)
                
                Text("\(totalItems) items found")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.purple.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Category Section
    
    private func categorySection(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        modes: [SmartCleaningMode]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Section total
                let sectionSize = modes.reduce(0) { $0 + $1.totalSize }
                Text(ByteCountFormatter.string(fromByteCount: sectionSize, countStyle: .file))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)
            }
            .padding(.horizontal, 16)
            
            // Mode cards grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(modes) { mode in
                    Button(action: {
                        selectedMode = mode
                        showingModeDetail = true
                    }) {
                        SmartCleanupModeCard(
                            mode: mode,
                            isHighestImpact: mode.id == highestImpactMode?.id && mode.totalSize > 0
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(mode.assetCount == 0)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var findMoreButton: some View {
        VStack(spacing: 8) {
            Button(action: expandSearch) {
                HStack(spacing: 10) {
                    if isExpandingSearch {
                        ProgressView()
                            .tint(.secondary)
                    } else {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.system(size: 20))
                    }
                    
                    Text(isExpandingSearch ? "Scanning Deeper..." : "Find More Results")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemGroupedBackground))
                .foregroundColor(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            }
            .disabled(isExpandingSearch || isLoading)
            .padding(.horizontal, 16)
            
            Text("Search continues further back in your library history")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Load Modes
    
    private func loadModes(forceRefresh: Bool = false) async {
        await MainActor.run {
            isLoading = true
        }
        
        // Use cached data for instant display, fresh scan when needed
        let modes = await SmartCleaningService.shared.loadHubModesCached(forceRefresh: forceRefresh, limitMultiplier: limitMultiplier)
        
        await MainActor.run {
            cleaningModes = modes
            isLoading = false
        }
    }
    
    private func expandSearch() {
        Task {
            await MainActor.run {
                isExpandingSearch = true
            }
            
            // Double the multiplier each time
            let nextMultiplier = limitMultiplier * 2
            
            // Fresh scan with new limit
            let modes = await SmartCleaningService.shared.loadHubModesCached(forceRefresh: true, limitMultiplier: nextMultiplier)
            
            await MainActor.run {
                limitMultiplier = nextMultiplier
                cleaningModes = modes
                isExpandingSearch = false
            }
        }
    }
}

// MARK: - Smart Cleanup Mode Card

private struct SmartCleanupModeCard: View {
    let mode: SmartCleaningMode
    let isHighestImpact: Bool
    
    private var colorForMode: Color {
        switch mode.color {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "gray": return .gray
        case "yellow": return .yellow
        case "pink": return .pink
        case "teal": return .teal
        default: return .blue
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Icon and badge row
            HStack {
                Image(systemName: mode.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(colorForMode)
                
                Spacer()
                
                if isHighestImpact {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("BIGGEST")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.orange, .red]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                } else if mode.id.isHighImpact && mode.assetCount > 0 {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }
            }
            
            // Title
            Text(mode.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            // Count and size
            HStack(spacing: 4) {
                Text("\(mode.assetCount)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(mode.assetCount > 0 ? colorForMode : .secondary)
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Text(mode.formattedSize)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            // Subtitle
            Text(mode.subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            mode.assetCount > 0
                ? Color(.systemBackground)
                : Color(.systemGray6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    mode.assetCount > 0
                        ? colorForMode.opacity(0.3)
                        : Color.clear,
                    lineWidth: 1
                )
        )
        .opacity(mode.assetCount > 0 ? 1.0 : 0.6)
    }
}

#Preview {
    SmartCleanupHubView()
}
