import SwiftUI
import UIKit

// MARK: - Interactive Swipe Demo View
struct InteractiveSwipeDemoView: View {
    let onContinue: () -> Void
    @State private var currentPhotoIndex = 0
    @State private var isAnimating = true
    @State private var showCompletion = false
    
    // Only 3 demo photos for quick demo
    // To use actual photos, add images named "demo_photo_1.jpg", "demo_photo_2.jpg", "demo_photo_3.jpg" 
    // to your Xcode project (drag into the project navigator, make sure "Copy items if needed" is checked)
    private let demoPhotos = [
        DemoPhoto(
            id: 1,
            imageName: nil,
            systemIcon: "photo",
            nameKey: "Screenshot",
            descriptionKey: "Old screenshot"
        ),
        DemoPhoto(
            id: 2,
            imageName: nil,
            systemIcon: "camera",
            nameKey: "Blurry Photo",
            descriptionKey: "Out of focus"
        ),
        DemoPhoto(
            id: 3,
            imageName: nil,
            systemIcon: "photo.stack",
            nameKey: "Duplicate",
            descriptionKey: "Already have this"
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            if !showCompletion {
                Spacer()
                
                // Title
                Text("Try Swiping")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)
                    .opacity(isAnimating ? 1.0 : 0.0)
                
                // Subtitle
                Text("Swipe through these sample photos")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                    .opacity(isAnimating ? 1.0 : 0.0)
                
                // Progress (cap at max count)
                Text("\(min(currentPhotoIndex + 1, demoPhotos.count)) of \(demoPhotos.count)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(red: 0.5, green: 0.2, blue: 0.8))
                    .padding(.bottom, 20)
                    .opacity(isAnimating ? 1.0 : 0.0)
                
                // Swipeable card
                if currentPhotoIndex < demoPhotos.count {
                    SwipeableDemoCard(
                        photo: demoPhotos[currentPhotoIndex],
                        onSwipe: handleSwipe
                    )
                    .id(demoPhotos[currentPhotoIndex].id)
                    .opacity(isAnimating ? 1.0 : 0.0)
                    .padding(.horizontal, 40)
                }
                
                Spacer()
                
                // Instructions
                HStack(spacing: 50) {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(Color(red: 0.95, green: 0.3, blue: 0.3))
                        Text("Delete")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(Color(red: 0.2, green: 0.7, blue: 0.4))
                        Text("Keep")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.bottom, 60)
                .opacity(isAnimating ? 1.0 : 0.0)
            } else {
                // Completion view
                Spacer()
                
                // Success icon
                ZStack {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.7, blue: 0.4).opacity(0.15))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Color(red: 0.2, green: 0.7, blue: 0.4))
                }
                .scaleEffect(isAnimating ? 1.0 : 0.8)
                .padding(.bottom, 40)
                
                Text("Great Job!")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)
                    .padding(.bottom, 8)
                
                Text("You've got the hang of it")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.gray)
                    .padding(.bottom, 40)
                
                Spacer()
                
                // Continue button
                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.5, green: 0.2, blue: 0.8),
                                    Color(red: 0.6, green: 0.3, blue: 0.9)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
    }
    
    private func handleSwipe(action: SwipeAction) {
        // Move to next photo
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPhotoIndex += 1
        }
        
        // Show completion if done
        if currentPhotoIndex >= demoPhotos.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    showCompletion = true
                    isAnimating = true
                }
            }
        }
    }
}

// MARK: - Demo Photo Model
struct DemoPhoto {
    let id: Int
    let imageName: String? // Name of image file in bundle (e.g., "demo_photo_1")
    let systemIcon: String // Fallback SF Symbol icon
    let nameKey: LocalizedStringKey
    let descriptionKey: LocalizedStringKey
}

// MARK: - Swipeable Demo Card
struct SwipeableDemoCard: View {
    let photo: DemoPhoto
    let onSwipe: (SwipeAction) -> Void
    
    @State private var dragOffset = CGSize.zero
    @State private var rotation: Double = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Photo placeholder with modern design
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.5, green: 0.2, blue: 0.8).opacity(0.1),
                                Color(red: 0.6, green: 0.3, blue: 0.9).opacity(0.05)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 350)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                
                // Show actual image if available, otherwise show icon placeholder
        VStack(spacing: 20) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 80, height: 80)
                
                Image(systemName: photo.systemIcon)
                    .font(.system(size: 36))
                    .foregroundColor(Color(red: 0.5, green: 0.2, blue: 0.8))
            }
            
            // Photo info
            VStack(spacing: 8) {
                Text(photo.nameKey)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(photo.descriptionKey)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.gray)
            }
        }
                
                // Swipe indicators
                if abs(dragOffset.width) > 30 {
                    VStack {
                        Spacer()
                        HStack {
                            if dragOffset.width < -30 {
                                Spacer()
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(Color(red: 0.95, green: 0.3, blue: 0.3))
                                    .opacity(min(Double(abs(dragOffset.width)) / 100, 1.0))
                                    .padding(.trailing, 30)
                                Spacer()
                            } else if dragOffset.width > 30 {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(Color(red: 0.2, green: 0.7, blue: 0.4))
                                    .opacity(min(Double(abs(dragOffset.width)) / 100, 1.0))
                                    .padding(.leading, 30)
                                Spacer()
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
        .offset(dragOffset)
        .rotationEffect(.degrees(rotation))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragOffset = value.translation
                    rotation = Double(value.translation.width / 25)
                }
                .onEnded { value in
                    let threshold: CGFloat = 100
                    
                    if abs(value.translation.width) > threshold {
                        // Swipe completed - animate off screen
                        let direction: CGFloat = value.translation.width > 0 ? 1 : -1
                        withAnimation(.easeOut(duration: 0.3)) {
                            dragOffset = CGSize(width: direction * 500, height: value.translation.height)
                            rotation = Double(direction * 15)
                        }
                        
                        // Call completion almost immediately so next card appears without pause
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            let action: SwipeAction = value.translation.width > 0 ? .keep : .delete
                            onSwipe(action)
                        }
                    } else {
                        // Snap back
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = .zero
                            rotation = 0
                        }
                    }
                }
        )
    }
}

#Preview {
    InteractiveSwipeDemoView {
    }
}
