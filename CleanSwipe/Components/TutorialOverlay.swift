import SwiftUI

struct TutorialOverlay: View {
    @Binding var showTutorial: Bool
    @State private var fingerOffset: CGSize = .zero
    @State private var animateContent = false
    
    var body: some View {
        ZStack {
            // Semi-transparent overlay
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 12) {
                    Text("Quick Guide")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Here's how to use CleanSwipe")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.top, 60)
                .opacity(animateContent ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.6), value: animateContent)
                
                // Swipe animation area
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.clear)
                        .frame(width: 280, height: 180)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.4), lineWidth: 2)
                        )
                    
                    // Animated finger
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(-15))
                        .offset(fingerOffset)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: fingerOffset)
                    
                    // Swipe direction indicators
                    HStack(spacing: 50) {
                        VStack(spacing: 6) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.red)
                            Text("Delete")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.red)
                        }
                        
                        VStack(spacing: 6) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.green)
                            Text("Keep")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green)
                        }
                    }
                    .opacity(0.8)
                }
                .opacity(animateContent ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.6).delay(0.2), value: animateContent)
                
                // Key information
                VStack(spacing: 16) {
                    // Swipe instructions
                    VStack(spacing: 8) {
                        Text("Swipe left to delete, right to keep")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Safety info
                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.green)
                            
                            Text("Photos are processed in batches of 10")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                            
                            Spacer()
                        }
                        
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.blue)
                            
                            Text("Review and confirm before any deletion")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                            
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 30)
                }
                .opacity(animateContent ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.6).delay(0.4), value: animateContent)
                
                Spacer()
                
                // Menu hint
                VStack(spacing: 8) {
                    Text("💡 Tip: Use the menu to choose filters and view stats")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                .opacity(animateContent ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.6).delay(0.6), value: animateContent)
                
                // Get Started button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showTutorial = false
                    }
                }) {
                    Text("Get Started!")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
                .opacity(animateContent ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.6).delay(0.8), value: animateContent)
            }
        }
        .onAppear {
            animateContent = true
            // Start finger animation
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                fingerOffset = CGSize(width: 60, height: -20)
            }
        }
    }
}

// MARK: - Tutorial Feature Row Helper
struct TutorialFeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
} 