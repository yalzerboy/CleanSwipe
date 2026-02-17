import SwiftUI
import Photos

struct PhotoThumbnailView: View {
    let asset: PHAsset
    let onUndo: () -> Void
    var size: CGFloat = 100
    var showUndoButton: Bool = true
    var onTap: (() -> Void)? = nil
    
    @State private var image: UIImage?
    private let imageManager = PHImageManager.default()
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size, height: size)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            }

            // Undo button as overlay badge
            if showUndoButton {
                Button(action: onUndo) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: size * 0.25, height: size * 0.25)
                            .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                        Image(systemName: "arrow.uturn.left")
                            .font(.system(size: size * 0.12, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                }
                .padding(2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            onTap?()
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        
        let targetSize = CGSize(width: size * UIScreen.main.scale, height: size * UIScreen.main.scale)
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            DispatchQueue.main.async {
                if let image = image {
                    self.image = image
                }
            }
        }
    }
}

// MARK: - Expanded Photo View for Review Screen
struct ExpandedPhotoView: View {
    let asset: PHAsset
    let onUndo: () -> Void
    let onDismiss: () -> Void
    
    @State private var image: UIImage?
    private let imageManager = PHImageManager.default()
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            VStack(spacing: 20) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                }
                
                Spacer()
                
                // Large photo
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: UIScreen.main.bounds.width - 40)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 300, height: 300)
                        .overlay(
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        )
                }
                
                Spacer()
                
                // Undo button
                Button(action: {
                    onUndo()
                    onDismiss()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.uturn.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Undo Delete")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            loadFullImage()
        }
    }
    
    private func loadFullImage() {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        
        let screenSize = UIScreen.main.bounds.size
        let targetSize = CGSize(width: screenSize.width * UIScreen.main.scale, height: screenSize.height * UIScreen.main.scale)
        
        imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            DispatchQueue.main.async {
                if let image = image {
                    self.image = image
                }
            }
        }
    }
}
