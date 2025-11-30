import SwiftUI
import Photos

struct PhotoThumbnailView: View {
    let asset: PHAsset
    let onUndo: () -> Void
    
    @State private var image: UIImage?
    private let imageManager = PHImageManager.default()
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 100, height: 100)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            }
            
            // Undo button
            VStack {
                HStack {
                    Spacer()
                    Button(action: onUndo) {
                        Image(systemName: "arrow.uturn.left.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                    .padding(4)
                }
                Spacer()
            }
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
        
        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(width: 100.0 * UIScreen.main.scale, height: 100.0 * UIScreen.main.scale),
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