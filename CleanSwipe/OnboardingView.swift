import SwiftUI
import AVKit

struct OnboardingView: View {
    @State private var showMainApp = false
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            // Video Player
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        // Configure player for autoplay and looping
                        player.actionAtItemEnd = .none
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
                    .overlay {
                        // Gradient overlay for better text visibility
                        LinearGradient(
                            gradient: Gradient(colors: [.black.opacity(0.2), .black.opacity(0.4)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
            
            VStack(spacing: 30) {
                Spacer()
                
                // Subtitle
                Text("Welcome to CleanSwipe")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text("Swipe right to keep, left to delete.\nOrganize your photos with simple gestures.")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Get Started Button
                Button(action: {
                    showMainApp = true
                }) {
                    Text("Get Started")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.blue)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            setupPlayer()
        }
        .fullScreenCover(isPresented: $showMainApp) {
            ContentView()
        }
    }
    
    private func setupPlayer() {
        guard let url = Bundle.main.url(forResource: "onboarding_video", withExtension: "mp4") else {
            print("Failed to find video file")
            return
        }
        
        let player = AVPlayer(url: url)
        
        // Add loop observer
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        
        self.player = player
    }
}

#Preview {
    OnboardingView()
} 