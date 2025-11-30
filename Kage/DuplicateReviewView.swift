//
//  DuplicateReviewView.swift
//  Kage
//
//  Created by AI Assistant on 09/11/2025.
//

import SwiftUI
import Photos
import UIKit

struct DuplicateReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = DuplicateReviewViewModel()
    @State private var showDeletionAlert = false
    @State private var alertMessage: String?
    @State private var previewAsset: DuplicateAssetPreviewContext?
    @State private var isDismissing = false
    
    private func performDismissal() {
        guard !isDismissing else { return }
        isDismissing = true

        // First dismiss any presented modals
        previewAsset = nil
        showDeletionAlert = false
        alertMessage = nil

        // Dismiss immediately - operations will be cancelled in background
        dismiss()

        // Cancel any ongoing operations on background thread to ensure no UI blocking
        DispatchQueue.global(qos: .background).async {
            self.viewModel.cancelScanning()
            self.viewModel.cancelDeletionIfPossible()
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    content
                    footer
                }
            }
            .navigationTitle("Review Duplicates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        performDismissal()
                    }
                    .disabled(isDismissing)
                }
            }
            .onAppear {
                if viewModel.groups.isEmpty && !viewModel.isLoading {
                    viewModel.reload()
                }
            }
            .onDisappear {
                viewModel.cancelScanning()
                // Reset dismissal state in case it was set but dismissal failed
                isDismissing = false
            }
            .onChange(of: viewModel.deletionMessage) { message in
                alertMessage = message
                showDeletionAlert = message != nil
            }
            .alert(alertMessage ?? "", isPresented: $showDeletionAlert, actions: {
                Button("OK", role: .cancel) {
                    alertMessage = nil
                }
            })
            .fullScreenCover(item: $previewAsset) { context in
                DuplicateAssetPreview(asset: context.asset) {
                    previewAsset = nil
                }
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.groups.isEmpty {
            VStack(spacing: 16) {
                badgeHeader
                if let progress = viewModel.scanProgress {
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 220)
                    Text("\(Int(progress * 100))% complete")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                } else {
                    ProgressView()
                }
                Text("Scanning your library…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
                Text("This may take a little while.")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
            VStack(spacing: 12) {
                badgeHeader
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
                Text("We couldn’t finish scanning.")
                    .font(.headline)
                Text(error)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button {
                    viewModel.reload(userInitiated: true)
                } label: {
                    Text("Try Again")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.groups.isEmpty {
            VStack(spacing: 12) {
                badgeHeader
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 34))
                    .foregroundColor(.green)
                Text("No duplicates found")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("Amazing! We’ll keep an eye on new photos and let you know when we spot duplicates.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Button {
                    viewModel.reload(userInitiated: true)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Scan again")
                    }
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 18, pinnedViews: []) {
                    badgeHeader
                    if let progress = viewModel.scanProgress, viewModel.isScanningWithProgress {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "arrow.2.squarepath")
                                    .foregroundColor(.blue)
                                Text("Scanning your library")
                                    .font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Text("\(Int(progress * 100))%")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            ProgressView(value: progress, total: 1.0)
                                .progressViewStyle(.linear)
                        }
                        .padding()
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 16)
                    }
                    
                    Button {
                        viewModel.requestMoreDuplicates()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("Find more duplicates")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(viewModel.isLoading || viewModel.deletionInProgress)
                    .padding(.horizontal, 16)
                    .buttonStyle(.borderedProminent)
                    .tint(.blue.opacity(0.75))
                    
                    ForEach(viewModel.groups) { group in
                        DuplicateGroupSection(
                            group: group,
                            isLoadingMore: viewModel.isLoadingMore && group.id == viewModel.groups.last?.id,
                            selectionProvider: { viewModel.isSelected(assetID: $0, in: group.id) },
                            onToggle: { assetID in viewModel.toggleSelection(assetID: assetID, groupID: group.id) },
                            onSelectAll: { viewModel.selectAll(in: group.id) },
                            onDeselectAll: { viewModel.deselectAll(in: group.id) },
                            onPreview: { asset in
                                previewAsset = DuplicateAssetPreviewContext(asset: asset)
                            }
                        )
                        .padding(.horizontal, 16)
                        .onAppear {
                            viewModel.loadMoreIfNeeded(currentGroup: group)
                        }
                    }
                    
                    if viewModel.hasMore {
                        Button(action: {
                            Task { await viewModel.loadNextPage(forceRefresh: false) }
                        }) {
                            HStack(spacing: 8) {
                                if viewModel.isLoadingMore {
                                    ProgressView()
                                }
                                Text(viewModel.isLoadingMore ? "Loading…" : "Show more duplicate sets")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(viewModel.isLoadingMore)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    } else {
                        Spacer(minLength: 20)
                    }
                }
                .padding(.vertical, 20)
            }
        }
    }
    
    private var footer: some View {
        VStack(spacing: 12) {
            Divider()
            
            let selectedCount = viewModel.totalSelectedCount()
            Button(action: {
                Task {
                    _ = await viewModel.deleteSelected()
                }
            }) {
                HStack {
                    if viewModel.deletionInProgress {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(selectedCount > 0 ? "Delete \(selectedCount) selected" : "Select photos to delete")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(selectedCount > 0 ? Color.red : Color.gray.opacity(0.35))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(selectedCount == 0 || viewModel.deletionInProgress)
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .background(Color(.systemBackground))
    }
    
    private var badgeHeader: some View {
        HStack {
            Spacer()
            BetaCornerBadge()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .allowsHitTesting(false)
    }
}

// MARK: - Group Section

private struct DuplicateGroupSection: View {
    let group: DuplicateGroup
    let isLoadingMore: Bool
    let selectionProvider: (String) -> Bool
    let onToggle: (String) -> Void
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void
    let onPreview: (PHAsset) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(group.assets) { asset in
                        DuplicateAssetThumbnail(
                            asset: asset.asset,
                            isSelected: selectionProvider(asset.id),
                            isPrimary: asset.isPrimary,
                            distanceScore: asset.distanceScore,
                            onToggleSelection: { onToggle(asset.id) },
                            onPreview: { onPreview(asset.asset) }
                        )
                    }
                }
                .padding(.vertical, 6)
            }
            
            if isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.kind.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                Text(group.subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Menu {
                Button("Select all for deletion") {
                    onSelectAll()
                }
                Button("Clear selection") {
                    onDeselectAll()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Asset Thumbnail

private struct DuplicateAssetThumbnail: View {
    let asset: PHAsset
    let isSelected: Bool
    let isPrimary: Bool
    let distanceScore: Float
    let onToggleSelection: () -> Void
    let onPreview: () -> Void
    
    @State private var image: UIImage?
    
    private var targetSize: CGSize {
        CGSize(width: 140.0 * UIScreen.main.scale, height: 140.0 * UIScreen.main.scale)
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                }
            }
            .frame(width: 140, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.red.opacity(0.9) : Color.clear, lineWidth: 3)
            )
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(distanceDescription)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    Text(selectionLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(selectionColor.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(8)
            }
            
            Button(action: {
                onToggleSelection()
            }) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .red : .white)
                    .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.35))
                            .frame(width: 32, height: 32)
                    )
            }
            .padding(10)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture(perform: onPreview)
        .task(id: asset.localIdentifier) {
            await loadThumbnail()
        }
    }
    
    private var distanceDescription: String {
        if distanceScore == 0 {
            return "Reference"
        } else if distanceScore < 0.06 {
            return "Almost identical"
        } else if distanceScore < 0.1 {
            return "Very close"
        } else {
            return "Similar"
        }
    }
    
    private func loadThumbnail() async {
        guard image == nil else { return }
        let cache = PhotoLibraryCache.shared
        if let thumbnail = await cache.requestThumbnail(for: asset, targetSize: targetSize) {
            await MainActor.run {
                self.image = thumbnail
            }
        }
    }
    
    private var selectionLabel: String {
        if isSelected {
            return "Marked to delete"
        } else if isPrimary {
            return "Default keep"
        } else {
            return "Keep"
        }
    }
    
    private var selectionColor: Color {
        if isSelected {
            return .red
        } else if isPrimary {
            return .blue
        } else {
            return .green
        }
    }
}

// MARK: - Preview Context

private struct DuplicateAssetPreviewContext: Identifiable {
    let id = UUID()
    let asset: PHAsset
}

private struct DuplicateAssetPreview: View {
    let asset: PHAsset
    let onDismiss: () -> Void
    
    @State private var image: UIImage?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                } else {
                    ProgressView("Loading…")
                        .tint(.white)
                        .foregroundColor(.white)
                }
            }
            .padding()
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.85))
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .onTapGesture {
            onDismiss()
        }
        .task(id: asset.localIdentifier) {
            await loadPreview()
        }
    }
    
    private func loadPreview() async {
        guard image == nil else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        
        let scale = UIScreen.main.scale
        let bounds = UIScreen.main.bounds
        let targetSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        
        let fetched: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded {
                    return
                }
                continuation.resume(returning: image)
            }
        }
        
        await MainActor.run {
            self.image = fetched
        }
    }
}
