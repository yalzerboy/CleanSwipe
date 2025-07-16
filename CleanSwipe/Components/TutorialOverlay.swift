import SwiftUI

struct TutorialOverlay: View {
    @Binding var showTutorial: Bool
    @State private var tutorialTimer: Timer?
    @State private var fingerOffset: CGSize = .zero
    @State private var showingTutorialOverlay = false
    
    var body: some View {
        ZStack {
            // Semi-transparent overlay
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                // Tutorial content area
                VStack(spacing: 40) {
                    // Finger swipe animation
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.clear)
                            .frame(width: 300, height: 200)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                            )
                        
                        // Animated finger
                        Image(systemName: "hand.point.up.left.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .rotationEffect(.degrees(-15))
                            .offset(fingerOffset)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: fingerOffset)
                    }
                    
                    // Instructions
                    VStack(spacing: 12) {
                        Text("Swipe to Keep or Delete")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 30) {
                            HStack {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 20))
                                    .foregroundColor(.red)
                                Text("Delete")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.red)
                            }
                            
                            HStack {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 20))
                                    .foregroundColor(.green)
                                Text("Keep")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Menu highlight text
                VStack(spacing: 8) {
                    Text("↑ Click here to change viewing options")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.yellow)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: showingTutorialOverlay)
                    
                    Text("Tap anywhere to continue")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.bottom, 60)
            }
            .padding()
        }
        .opacity(showingTutorialOverlay ? 1 : 0)
        .onAppear {
            if showTutorial {
                startTutorial()
            }
        }
        .onChange(of: showTutorial) { newValue in
            if newValue && !showingTutorialOverlay {
                startTutorial()
            }
        }
        .onTapGesture {
            dismissTutorial()
        }
    }
    
    private func startTutorial() {
        showingTutorialOverlay = true
        
        // Start finger animation
        fingerOffset = CGSize(width: -80, height: 0)
        
        // Animate finger back and forth
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            fingerOffset = CGSize(width: 80, height: 0)
        }
        
        // Auto-dismiss after 3 seconds
        tutorialTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            dismissTutorial()
        }
    }
    
    private func dismissTutorial() {
        tutorialTimer?.invalidate()
        tutorialTimer = nil
        
        withAnimation(.easeOut(duration: 0.3)) {
            showingTutorialOverlay = false
        }
        
        // Mark tutorial as completed
        showTutorial = false
    }
} 