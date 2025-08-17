import SwiftUI
import AVKit
import RevenueCatUI
import RevenueCat

// MARK: - Splash Screen
struct SplashView: View {
    let onComplete: () -> Void
    
    var body: some View {
        ZStack {
            // Baby blue background
            Color(red: 0.7, green: 0.85, blue: 1.0)
                .ignoresSafeArea()
            
            // White CleanSwipe text
            Text("CleanSwipe")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .onAppear {
            // Show splash for 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onComplete()
            }
        }
    }
}

// MARK: - Main Onboarding Flow
struct OnboardingFlowView: View {
    let onComplete: (ContentType) -> Void
    @State private var currentStep: OnboardingStep = .welcome
    @State private var userAge: String = ""
    @State private var photoCount: PhotoCount? = nil
    @State private var cleaningFrequency: CleaningFrequency? = nil
    @State private var contentType: ContentType? = nil
    @State private var loadingProgress: Double = 0.0
    
    var body: some View {
        ZStack {
            // Baby blue background for all slides
            Color(red: 0.7, green: 0.85, blue: 1.0)
                .ignoresSafeArea()
            
            switch currentStep {
            case .welcome:
                WelcomeView {
                    currentStep = .benefits
                }
            case .benefits:
                BenefitsView {
                    currentStep = .howTo
                }
            case .howTo:
                HowToView {
                    currentStep = .age
                }
            case .age:
                AgeView(selectedAge: $userAge) {
                    currentStep = .photoCount
                }
            case .photoCount:
                PhotoCountView(selectedCount: $photoCount) {
                    currentStep = .cleaningFrequency
                }
            case .cleaningFrequency:
                CleaningFrequencyView(selectedFrequency: $cleaningFrequency) {
                    currentStep = .contentType
                }
            case .contentType:
                ContentTypeView(selectedType: $contentType) {
                    if contentType != nil {
                        currentStep = .preparing
                    }
                }
            case .preparing:
                PreparingView(progress: $loadingProgress) {
                    currentStep = .freeTrialIntro
                }
            case .freeTrialIntro:
                FreeTrialIntroView {
                    currentStep = .finalContinue
                }
            case .finalContinue:
                FinalContinueView(onSkip: { 
                    onComplete(contentType ?? .photos) 
                }, onContinue: { 
                    onComplete(contentType ?? .photos)
                })
            }
        }
    }
}

// MARK: - Onboarding Steps
// Note: Enums moved to Models/ContentType.swift

// MARK: - Welcome View (Animated text onboarding)
struct WelcomeView: View {
    let onContinue: () -> Void
    @State private var animatedText = ""
    @State private var currentIndex = 0
    @State private var isAnimating = false
    
    private let fullText = "With just a few mins a day, swipe your way to a clean, organised photo library"
    private let animationSpeed: TimeInterval = 0.03
    
    var body: some View {
        ZStack {
            // Baby blue background
            Color(red: 0.7, green: 0.85, blue: 1.0)
                    .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // Static CleanSwipe text in blocky font
                Text("CleanSwipe")
                    .font(.system(size: 48, weight: .black, design: .default))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                // Animated description text
                Text(animatedText)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .onAppear {
                        startTextAnimation()
                    }
                
                Button(action: onContinue) {
                    Text("Let's go")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.9, green: 0.4, blue: 0.7), // Pink
                                    Color(red: 0.4, green: 0.6, blue: 0.9)  // Blue
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
                .opacity(isAnimating ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.5).delay(2.5), value: isAnimating)
            }
        }
        }
    
    private func startTextAnimation() {
        isAnimating = true
        animateText()
    }
    
    private func animateText() {
        guard currentIndex < fullText.count else {
            return
        }
        
        let index = fullText.index(fullText.startIndex, offsetBy: currentIndex)
        animatedText += String(fullText[index])
        currentIndex += 1
        
        DispatchQueue.main.asyncAfter(deadline: .now() + animationSpeed) {
            animateText()
        }
    }
}

// MARK: - How To View
struct HowToView: View {
    let onContinue: () -> Void
    @State private var animateLeft = false
    @State private var animateRight = false
    @State private var animateTitle = false
    @State private var animateDescription = false
    
    var body: some View {
        ZStack {
            // Animated background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.7, green: 0.85, blue: 1.0),
                    Color(red: 0.6, green: 0.8, blue: 0.95),
                    Color(red: 0.7, green: 0.85, blue: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .opacity(animateTitle ? 1.0 : 0.8)
            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animateTitle)
            
            VStack(spacing: 0) {
                // Header with animated title
                VStack(spacing: 16) {
                Text("Quick How-To")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        .scaleEffect(animateTitle ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateTitle)
                    
                    Text("Master the art of photo organization")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(animateTitle ? 1.0 : 0.7)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateTitle)
                }
                .padding(.top, 60)
                .padding(.horizontal, 40)
                
                // Swipe instructions with animations
                VStack(spacing: 40) {
                    // Swipe Left to Delete
                    SwipeInstructionCard(
                        icon: "trash.circle.fill",
                        title: "Swipe Left",
                        subtitle: "to delete",
                        color: .red,
                        direction: .left,
                        isAnimating: animateLeft
                    )
                    
                    // Swipe Right to Keep
                    SwipeInstructionCard(
                        icon: "heart.circle.fill",
                        title: "Swipe Right",
                        subtitle: "to keep",
                        color: .green,
                        direction: .right,
                        isAnimating: animateRight
                    )
                }
                .padding(.top, 50)
                .padding(.horizontal, 30)
                
                Spacer()
                
                // Description with fade-in animation
                VStack(spacing: 16) {
                    Text("✨ De-clutter your phone and relive memories with every swipe! ✨")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 30)
                        .opacity(animateDescription ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 1.0).delay(0.5), value: animateDescription)
                    
                    // Batch processing info
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 20))
                            .foregroundColor(.green)
                            
                            Text("Safe & Secure")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
            }
            
                        Text("Photos are processed in batches of 10. Review and confirm before any deletion. Everything can be undone!")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.green.opacity(0.4), lineWidth: 1)
                            )
                    )
                    .opacity(animateDescription ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 1.0).delay(0.8), value: animateDescription)
                    
                    // Animated sparkles
                    HStack(spacing: 20) {
                        ForEach(0..<3, id: \.self) { index in
                            Image(systemName: "sparkles")
                                .font(.system(size: 16))
                                .foregroundColor(.yellow)
                                .opacity(animateDescription ? 1.0 : 0.0)
                                .animation(.easeInOut(duration: 1.0).delay(1.2 + Double(index) * 0.2), value: animateDescription)
                        }
                    }
                }
                .padding(.bottom, 30)
                
                // Continue button with gradient and animation
            Button(action: onContinue) {
                    HStack(spacing: 12) {
                        Text("Let's Get Started!")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
                    .scaleEffect(animateDescription ? 1.0 : 0.95)
                    .animation(.easeInOut(duration: 1.0).delay(1.0), value: animateDescription)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        }
        .onAppear {
            // Start animations
            animateTitle = true
            animateLeft = true
            animateRight = true
            animateDescription = true
        }
    }
}

// MARK: - Swipe Instruction Card
struct SwipeInstructionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let direction: SwipeDirection
    let isAnimating: Bool
    
    @State private var cardOffset: CGFloat = 0
    @State private var iconScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.0
    
    enum SwipeDirection {
        case left, right
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Icon section
            ZStack {
                // Glow effect
                Circle()
                    .fill(color)
                    .frame(width: 80, height: 80)
                    .blur(radius: 20)
                    .opacity(glowOpacity)
                    .scaleEffect(iconScale)
                
                // Main icon
                Image(systemName: icon)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(color)
                    .scaleEffect(iconScale)
                    .shadow(color: color.opacity(0.5), radius: 8, x: 0, y: 4)
            }
            .frame(width: 80, height: 80)
            
            // Text section
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.leading, 24)
            
            Spacer()
            
            // Swipe arrow indicator
            VStack(spacing: 8) {
                Image(systemName: direction == .left ? "arrow.left" : "arrow.right")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(color)
                    .offset(x: cardOffset)
                    .opacity(isAnimating ? 1.0 : 0.5)
                
                Text(direction == .left ? "←" : "→")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(color.opacity(0.7))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(color.opacity(0.3), lineWidth: 2)
                )
        )
        .shadow(color: color.opacity(0.2), radius: 10, x: 0, y: 5)
        .onAppear {
            // Start card animations
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                cardOffset = direction == .left ? -10 : 10
                iconScale = 1.1
                glowOpacity = 0.6
            }
        }
    }
}

// MARK: - Benefits View
struct BenefitsView: View {
    let onContinue: () -> Void
    @State private var animateTitle = false
    @State private var animateIcon = false
    @State private var animateDescription = false
    @State private var animateButton = false
    
    var body: some View {
        ZStack {
            // Animated background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.7, green: 0.85, blue: 1.0),
                    Color(red: 0.6, green: 0.8, blue: 0.95),
                    Color(red: 0.7, green: 0.85, blue: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .opacity(animateTitle ? 1.0 : 0.8)
            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animateTitle)
            
            VStack(spacing: 0) {
                // Header with animated title
                VStack(spacing: 16) {
                Text("Enjoy the Free Space")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        .scaleEffect(animateTitle ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateTitle)
                
                Text("No more \"out of storage\"")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                        .opacity(animateTitle ? 1.0 : 0.7)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateTitle)
                }
                .padding(.top, 60)
                .padding(.horizontal, 40)
                
                // Animated icon section
                VStack(spacing: 24) {
                    ZStack {
                        // Glow effect
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 120, height: 120)
                            .blur(radius: 30)
                            .opacity(animateIcon ? 0.6 : 0.0)
                            .scaleEffect(animateIcon ? 1.2 : 1.0)
                        
                        // Main icon
                Image(systemName: "icloud.and.arrow.up")
                            .font(.system(size: 60, weight: .bold))
                    .foregroundColor(.blue)
                            .scaleEffect(animateIcon ? 1.1 : 1.0)
                            .shadow(color: .blue.opacity(0.5), radius: 12, x: 0, y: 6)
                    }
                    .frame(height: 120)
                
                Text("Free up space on your device and keep your favorite memories")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 30)
                        .opacity(animateDescription ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 1.0).delay(0.5), value: animateDescription)
            }
                .padding(.top, 50)
            
            Spacer()
            
                // Continue button with gradient and animation
            Button(action: onContinue) {
                    HStack(spacing: 12) {
                        Text("Sounds Great!")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
                    .scaleEffect(animateButton ? 1.0 : 0.95)
                    .animation(.easeInOut(duration: 1.0).delay(1.0), value: animateButton)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        }
        .onAppear {
            // Start animations
            animateTitle = true
            animateIcon = true
            animateDescription = true
            animateButton = true
        }
    }
}

// MARK: - Age View
struct AgeView: View {
    @Binding var selectedAge: String
    let onContinue: () -> Void
    @State private var animateTitle = false
    @State private var animateOptions = false
    @State private var animateButton = false
    
    private let ageRanges = ["Under 18", "18-24", "25-34", "35-44", "45-54", "55-64", "65+"]
    
    var body: some View {
        ZStack {
            // Animated background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.7, green: 0.85, blue: 1.0),
                    Color(red: 0.6, green: 0.8, blue: 0.95),
                    Color(red: 0.7, green: 0.85, blue: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .opacity(animateTitle ? 1.0 : 0.8)
            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animateTitle)
            
            VStack(spacing: 0) {
                // Header with animated title
            VStack(spacing: 16) {
                    Text("What's your age?")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        .scaleEffect(animateTitle ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateTitle)
                    
                }
                .padding(.top, 60)
                .padding(.horizontal, 40)
                
                // Age options with animations
                VStack(spacing: 12) {
                    ForEach(Array(ageRanges.enumerated()), id: \.element) { index, age in
                        AgeOptionButton(
                            age: age,
                            isSelected: selectedAge == age,
                            onTap: { selectedAge = age },
                            animationDelay: Double(index) * 0.1,
                            isAnimating: animateOptions
                        )
                    }
                }
                .padding(.top, 40)
                .padding(.horizontal, 30)
            
            Spacer()
            
                // Button section
            HStack(spacing: 20) {
                Button("Skip") {
                    onContinue()
                }
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .opacity(animateButton ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 1.0).delay(0.8), value: animateButton)
                
                Button(action: onContinue) {
                        HStack(spacing: 12) {
                    Text("Continue")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                            
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
                        .scaleEffect(animateButton ? 1.0 : 0.95)
                        .animation(.easeInOut(duration: 1.0).delay(1.0), value: animateButton)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        }
        .onAppear {
            // Start animations
            animateTitle = true
            animateOptions = true
            animateButton = true
        }
    }
}

// MARK: - Age Option Button
struct AgeOptionButton: View {
    let age: String
    let isSelected: Bool
    let onTap: () -> Void
    let animationDelay: Double
    let isAnimating: Bool
    
    @State private var buttonScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.0
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    // Glow effect for selected state
                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 28, height: 28)
                            .blur(radius: 8)
                            .opacity(glowOpacity)
                    }
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(isSelected ? .blue : .white.opacity(0.6))
                        .scaleEffect(buttonScale)
                }
                
                Text(age)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 2)
                    )
            )
            .shadow(color: isSelected ? .blue.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
            .scaleEffect(isAnimating ? 1.0 : 0.9)
            .opacity(isAnimating ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.6).delay(animationDelay), value: isAnimating)
        }
        .onAppear {
            if isSelected {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    buttonScale = 1.1
                    glowOpacity = 0.6
                }
            }
        }
        .onChange(of: isSelected) { newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    buttonScale = 1.1
                    glowOpacity = 0.6
                }
            } else {
                buttonScale = 1.0
                glowOpacity = 0.0
            }
        }
    }
}

// MARK: - Photo Count View
struct PhotoCountView: View {
    @Binding var selectedCount: PhotoCount?
    let onContinue: () -> Void
    @State private var animateTitle = false
    @State private var animateOptions = false
    @State private var animateButton = false
    
    var body: some View {
        ZStack {
            // Animated background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.7, green: 0.85, blue: 1.0),
                    Color(red: 0.6, green: 0.8, blue: 0.95),
                    Color(red: 0.7, green: 0.85, blue: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .opacity(animateTitle ? 1.0 : 0.8)
            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animateTitle)
            
            VStack(spacing: 0) {
                // Header with animated title
                VStack(spacing: 16) {
                    Text("How many photos do you have?")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        .scaleEffect(animateTitle ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateTitle)
                    
                }
                .padding(.top, 60)
                .padding(.horizontal, 40)
                
                // Photo count options with animations
                VStack(spacing: 12) {
                    ForEach(Array(PhotoCount.allCases.enumerated()), id: \.element) { index, count in
                        PhotoCountOptionButton(
                            count: count,
                            isSelected: selectedCount == count,
                            onTap: { selectedCount = count },
                            animationDelay: Double(index) * 0.1,
                            isAnimating: animateOptions
                        )
                    }
                }
                .padding(.top, 40)
                .padding(.horizontal, 30)
                
                Spacer()
                
                // Button section
        HStack(spacing: 20) {
            Button("Skip") {
                onContinue()
            }
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .opacity(animateButton ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 1.0).delay(0.8), value: animateButton)
            
            Button(action: onContinue) {
                        HStack(spacing: 12) {
                Text("Continue")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                            
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                    .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
                        .scaleEffect(animateButton ? 1.0 : 0.95)
                        .animation(.easeInOut(duration: 1.0).delay(1.0), value: animateButton)
            }
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 50)
    }
        }
        .onAppear {
            // Start animations
            animateTitle = true
            animateOptions = true
            animateButton = true
        }
    }
}

// MARK: - Photo Count Option Button
struct PhotoCountOptionButton: View {
    let count: PhotoCount
    let isSelected: Bool
    let onTap: () -> Void
    let animationDelay: Double
    let isAnimating: Bool
    
    @State private var buttonScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.0
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    // Glow effect for selected state
                    if isSelected {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 28, height: 28)
                            .blur(radius: 8)
                            .opacity(glowOpacity)
                    }
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(isSelected ? .green : .white.opacity(0.6))
                        .scaleEffect(buttonScale)
                }
                
                Text(count.rawValue)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.green.opacity(0.5) : Color.clear, lineWidth: 2)
                    )
            )
            .shadow(color: isSelected ? .green.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
            .scaleEffect(isAnimating ? 1.0 : 0.9)
            .opacity(isAnimating ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.6).delay(animationDelay), value: isAnimating)
        }
        .onAppear {
            if isSelected {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    buttonScale = 1.1
                    glowOpacity = 0.6
                }
            }
        }
        .onChange(of: isSelected) { newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    buttonScale = 1.1
                    glowOpacity = 0.6
                }
            } else {
                buttonScale = 1.0
                glowOpacity = 0.0
            }
        }
    }
}

// MARK: - Cleaning Frequency View
struct CleaningFrequencyView: View {
    @Binding var selectedFrequency: CleaningFrequency?
    let onContinue: () -> Void
    @State private var animateTitle = false
    @State private var animateOptions = false
    @State private var animateButton = false
    
    var body: some View {
        ZStack {
            // Animated background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.7, green: 0.85, blue: 1.0),
                    Color(red: 0.6, green: 0.8, blue: 0.95),
                    Color(red: 0.7, green: 0.85, blue: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .opacity(animateTitle ? 1.0 : 0.8)
            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animateTitle)
            
            VStack(spacing: 0) {
                // Header with animated title
                VStack(spacing: 16) {
                    Text("How often do you clean your photo gallery?")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        .scaleEffect(animateTitle ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateTitle)

                }
                .padding(.top, 60)
                .padding(.horizontal, 40)
                
                // Frequency options with animations
                VStack(spacing: 12) {
                    ForEach(Array(CleaningFrequency.allCases.enumerated()), id: \.element) { index, frequency in
                        FrequencyOptionButton(
                            frequency: frequency,
                            isSelected: selectedFrequency == frequency,
                            onTap: { selectedFrequency = frequency },
                            animationDelay: Double(index) * 0.1,
                            isAnimating: animateOptions
                        )
                    }
                }
                .padding(.top, 40)
                .padding(.horizontal, 30)
                
                Spacer()
                
                // Button section
        HStack(spacing: 20) {
            Button("Skip") {
                onContinue()
            }
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .opacity(animateButton ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 1.0).delay(0.8), value: animateButton)
            
            Button(action: onContinue) {
                        HStack(spacing: 12) {
                Text("Continue")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                            
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                    .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
                        .scaleEffect(animateButton ? 1.0 : 0.95)
                        .animation(.easeInOut(duration: 1.0).delay(1.0), value: animateButton)
            }
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 50)
    }
        }
        .onAppear {
            // Start animations
            animateTitle = true
            animateOptions = true
            animateButton = true
        }
    }
}

// MARK: - Frequency Option Button
struct FrequencyOptionButton: View {
    let frequency: CleaningFrequency
    let isSelected: Bool
    let onTap: () -> Void
    let animationDelay: Double
    let isAnimating: Bool
    
    @State private var buttonScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.0
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    // Glow effect for selected state
                    if isSelected {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 28, height: 28)
                            .blur(radius: 8)
                            .opacity(glowOpacity)
                    }
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(isSelected ? .orange : .white.opacity(0.6))
                        .scaleEffect(buttonScale)
                }
                
                Text(frequency.rawValue)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 2)
                    )
            )
            .shadow(color: isSelected ? .orange.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
            .scaleEffect(isAnimating ? 1.0 : 0.9)
            .opacity(isAnimating ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.6).delay(animationDelay), value: isAnimating)
        }
        .onAppear {
            if isSelected {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    buttonScale = 1.1
                    glowOpacity = 0.6
                }
            }
        }
        .onChange(of: isSelected) { newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    buttonScale = 1.1
                    glowOpacity = 0.6
                }
            } else {
                buttonScale = 1.0
                glowOpacity = 0.0
            }
        }
    }
}

// MARK: - Content Type View
struct ContentTypeView: View {
    @Binding var selectedType: ContentType?
    let onContinue: () -> Void
    @State private var animateTitle = false
    @State private var animateOptions = false
    @State private var animateButton = false
    
    var body: some View {
        ZStack {
            // Animated background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.7, green: 0.85, blue: 1.0),
                    Color(red: 0.6, green: 0.8, blue: 0.95),
                    Color(red: 0.7, green: 0.85, blue: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .opacity(animateTitle ? 1.0 : 0.8)
            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animateTitle)
            
            VStack(spacing: 0) {
                // Header with animated title
                VStack(spacing: 16) {
                    Text("What would you like to clean?")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        .scaleEffect(animateTitle ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateTitle)
                    
                    Text("You can change this later in settings")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(animateTitle ? 1.0 : 0.7)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateTitle)
                }
                .padding(.top, 60)
                .padding(.horizontal, 40)
                
                // Content type options with animations
                VStack(spacing: 12) {
                    ForEach(Array(ContentType.allCases.enumerated()), id: \.element) { index, type in
                        ContentTypeOptionButton(
                            type: type,
                            isSelected: selectedType == type,
                            onTap: { selectedType = type },
                            animationDelay: Double(index) * 0.1,
                            isAnimating: animateOptions
                        )
                    }
                }
                .padding(.top, 40)
                .padding(.horizontal, 30)
                
                Spacer()
                
                // Continue button with gradient and animation
        Button(action: onContinue) {
                    HStack(spacing: 12) {
            Text("Continue")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
                    .scaleEffect(animateButton ? 1.0 : 0.95)
                    .animation(.easeInOut(duration: 1.0).delay(1.0), value: animateButton)
        }
        .disabled(selectedType == nil)
                .opacity(selectedType != nil ? 1.0 : 0.6)
        .padding(.horizontal, 40)
        .padding(.bottom, 50)
            }
        }
        .onAppear {
            // Start animations
            animateTitle = true
            animateOptions = true
            animateButton = true
        }
    }
}

// MARK: - Content Type Option Button
struct ContentTypeOptionButton: View {
    let type: ContentType
    let isSelected: Bool
    let onTap: () -> Void
    let animationDelay: Double
    let isAnimating: Bool
    
    @State private var buttonScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.0
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                ZStack {
                    // Glow effect for selected state
                    if isSelected {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 28, height: 28)
                            .blur(radius: 8)
                            .opacity(glowOpacity)
                    }
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(isSelected ? .purple : .white.opacity(0.6))
                        .scaleEffect(buttonScale)
                }
                
                Text(type.rawValue)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.purple.opacity(0.5) : Color.clear, lineWidth: 2)
                    )
            )
            .shadow(color: isSelected ? .purple.opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
            .scaleEffect(isAnimating ? 1.0 : 0.9)
            .opacity(isAnimating ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.6).delay(animationDelay), value: isAnimating)
        }
        .onAppear {
            if isSelected {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    buttonScale = 1.1
                    glowOpacity = 0.6
                }
            }
        }
        .onChange(of: isSelected) { newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    buttonScale = 1.1
                    glowOpacity = 0.6
                }
            } else {
                buttonScale = 1.0
                glowOpacity = 0.0
            }
        }
    }
}

// MARK: - Preparing View
struct PreparingView: View {
    @Binding var progress: Double
    let onComplete: () -> Void
    @State private var timer: Timer?
    @State private var animateTitle = false
    @State private var animateProgress = false
    @State private var animateIcon = false
    @State private var animateCompletion = false
    
    var body: some View {
        ZStack {
            // Animated background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.7, green: 0.85, blue: 1.0),
                    Color(red: 0.6, green: 0.8, blue: 0.95),
                    Color(red: 0.7, green: 0.85, blue: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .opacity(animateTitle ? 1.0 : 0.8)
            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animateTitle)
            
            VStack(spacing: 0) {
                // Header with animated title
                VStack(spacing: 16) {
            Text("Thanks! Preparing your experience now")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        .scaleEffect(animateTitle ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateTitle)
                    
                    Text("Setting up everything just for you")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(animateTitle ? 1.0 : 0.7)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateTitle)
                }
                .padding(.top, 100)
                .padding(.horizontal, 40)
                
                // Animated icon section
                VStack(spacing: 30) {
                    ZStack {
                        // Glow effect
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 120, height: 120)
                            .blur(radius: 30)
                            .opacity(animateIcon ? 0.6 : 0.0)
                            .scaleEffect(animateIcon ? 1.2 : 1.0)
                        
                        // Main icon
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 60, weight: .bold))
                            .foregroundColor(.blue)
                            .scaleEffect(animateIcon ? 1.1 : 1.0)
                            .shadow(color: .blue.opacity(0.5), radius: 12, x: 0, y: 6)
                            .rotationEffect(.degrees(animateIcon ? 360 : 0))
                            .animation(.linear(duration: 3.0).repeatForever(autoreverses: false), value: animateIcon)
                    }
                    .frame(height: 120)
                    
                    // Progress section
            VStack(spacing: 20) {
                        // Custom progress bar
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 12)
                            
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue, Color.purple]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, UIScreen.main.bounds.width - 80) * clampedProgress, height: 12)
                                .animation(.easeInOut(duration: 0.3), value: clampedProgress)
                        }
                    .padding(.horizontal, 40)
                
                Text("\(Int(clampedProgress * 100))%")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .scaleEffect(animateProgress ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: animateProgress)
                    }
                    .opacity(animateProgress ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 1.0).delay(0.5), value: animateProgress)
                }
                .padding(.top, 60)
            
            Spacer()
                
                // Completion message
                if clampedProgress >= 1.0 {
                    VStack(spacing: 16) {
                        Text("✨ All set! ✨")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        
                        Text("Your personalized experience is ready")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(animateCompletion ? 1.0 : 0.0)
                    .scaleEffect(animateCompletion ? 1.0 : 0.8)
                    .animation(.easeInOut(duration: 1.0).delay(0.5), value: animateCompletion)
                    .padding(.bottom, 50)
                }
            }
        }
        .onAppear {
            // Start animations
            animateTitle = true
            animateIcon = true
            animateProgress = true
            
            // Start progress
            startProgress()
        }
        .onDisappear {
            timer?.invalidate()
        }
        .onChange(of: clampedProgress) { newValue in
            if newValue >= 1.0 {
                animateCompletion = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    onComplete()
                }
            }
        }
    }
    
    private var clampedProgress: Double {
        return max(0.0, min(progress, 1.0))
    }
    
    private func startProgress() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            if progress < 1.0 {
                progress = min(progress + 0.017, 1.0) // Clamp to 1.0
            } else {
                timer?.invalidate()
            }
        }
    }
}

// MARK: - Free Trial Intro View
struct FreeTrialIntroView: View {
    let onContinue: () -> Void
    @State private var paywallTrigger = 0
    @State private var animateTitle = false
    @State private var animateIcon = false
    @State private var animateBenefits = false
    @State private var animateButton = false
    @EnvironmentObject private var purchaseManager: PurchaseManager
    
    var body: some View {
        ZStack {
            // Animated background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.7, green: 0.85, blue: 1.0),
                    Color(red: 0.6, green: 0.8, blue: 0.95),
                    Color(red: 0.7, green: 0.85, blue: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .opacity(animateTitle ? 1.0 : 0.8)
            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animateTitle)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                // Header with animated title
                VStack(spacing: 16) {
                        Text("Unlock Your Photo Freedom")
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            .scaleEffect(animateTitle ? 1.05 : 1.0)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateTitle)
                    
                    Text("Experience CleanSwipe Premium for free")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(animateTitle ? 1.0 : 0.7)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateTitle)
                }
                .padding(.top, 60)
                .padding(.horizontal, 24)
                
                // Animated icon section
                VStack(spacing: 24) {
                    ZStack {
                        // Glow effect
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 120, height: 120)
                            .blur(radius: 30)
                            .opacity(animateIcon ? 0.6 : 0.0)
                            .scaleEffect(animateIcon ? 1.2 : 1.0)
                        
                        // Main icon with animation
                        Image(systemName: "crown.fill")
                            .font(.system(size: 60, weight: .bold))
                            .foregroundColor(.yellow)
                            .scaleEffect(animateIcon ? 1.1 : 1.0)
                            .shadow(color: .yellow.opacity(0.5), radius: 12, x: 0, y: 6)
                            .rotationEffect(.degrees(animateIcon ? 5 : -5))
                            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animateIcon)
                    }
                    .frame(height: 120)
                }
                .padding(.top, 40)
                
                // Benefits section with animations
                VStack(spacing: 16) {
                    BenefitRow(
                        icon: "infinity",
                        text: "Unlimited daily swipes",
                        delay: 0.0,
                        isAnimating: animateBenefits
                    )
                    
                    BenefitRow(
                        icon: "xmark.circle.fill",
                        text: "No advertisements",
                        delay: 0.2,
                        isAnimating: animateBenefits
                    )
                    
                    BenefitRow(
                        icon: "slider.horizontal.3",
                        text: "All photo categories & filters",
                        delay: 0.4,
                        isAnimating: animateBenefits
                    )
                    
                    BenefitRow(
                        icon: "chart.bar.fill",
                        text: "Detailed progress tracking",
                        delay: 0.6,
                        isAnimating: animateBenefits
                    )
                }
                .padding(20)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.top, 24)
                .padding(.horizontal, 24)
                
                Spacer(minLength: 24)
                
                // Persuasive text
                VStack(spacing: 12) {
                    Text("🎉 Start your free trial today!")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                        .multilineTextAlignment(.center)
            
                    Text("No commitment • Cancel anytime • No payment required")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .opacity(animateBenefits ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 1.0).delay(0.8), value: animateBenefits)
            
                // Buttons moved to safe area inset; leave some content bottom spacing
                Spacer(minLength: 16)
            }
            .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(action: {
                    paywallTrigger += 1
                }) {
                    HStack(spacing: 12) {
                        Text("Start Free Trial")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.yellow)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .blue.opacity(0.3), radius: 6, x: 0, y: 2)
                }

                Button(action: onContinue) {
                    Text("Continue with limited version")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: -2)
        }
        .presentPaywallIfNeeded(
            requiredEntitlementIdentifier: "Premium",
            purchaseCompleted: { customerInfo in
                onContinue()
            },
            restoreCompleted: { customerInfo in
                onContinue()
            }
        )
        .id(paywallTrigger)
        .onAppear {
            // Start animations
            animateTitle = true
            animateIcon = true
            animateBenefits = true
            animateButton = true
        }
    }
}

// MARK: - Benefit Row Helper
struct BenefitRow: View {
    let icon: String
    let text: String
    let delay: Double
    let isAnimating: Bool
    
    @State private var iconScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.0
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                // Glow effect
                Circle()
                    .fill(Color.blue)
                    .frame(width: 32, height: 32)
                    .blur(radius: 8)
                    .opacity(glowOpacity)
                    .scaleEffect(iconScale)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.blue)
                    .scaleEffect(iconScale)
            }
            .frame(width: 32, height: 32)
            
            Text(text)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            
            Spacer()
        }
        .opacity(isAnimating ? 1.0 : 0.0)
        .offset(x: isAnimating ? 0 : -20)
        .animation(.easeInOut(duration: 0.6).delay(delay), value: isAnimating)
        .onAppear {
            if isAnimating {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    iconScale = 1.1
                    glowOpacity = 0.4
                }
            }
        }
    }
}


// MARK: - Feature Row Helper
struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
}



// MARK: - Final Continue View
struct FinalContinueView: View {
    let onSkip: () -> Void
    let onContinue: () -> Void
    @State private var animateTitle = false
    @State private var animateFeatures = false
    @State private var animateButton = false
    @State private var animateConfetti = false
    
    var body: some View {
        ZStack {
            // Animated background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.7, green: 0.85, blue: 1.0),
                    Color(red: 0.6, green: 0.8, blue: 0.95),
                    Color(red: 0.7, green: 0.85, blue: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .opacity(animateTitle ? 1.0 : 0.8)
            .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animateTitle)
            
            // Animated confetti
            if animateConfetti {
                ForEach(0..<20, id: \.self) { index in
                    ConfettiPiece(
                        delay: Double(index) * 0.1,
                        color: [Color.blue, Color.purple, Color.green, Color.orange, Color.pink].randomElement()!
                    )
                }
            }
            
            VStack(spacing: 0) {
                // Close button
            HStack {
                Button(action: onSkip) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
                // Header with animated title
                VStack(spacing: 16) {
                    Text("🎉 You're all set!")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        .scaleEffect(animateTitle ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateTitle)
                
            Text("Start cleaning up your photos and videos with CleanSwipe")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(animateTitle ? 1.0 : 0.7)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateTitle)
                }
                .padding(.top, 40)
                    .padding(.horizontal, 40)
                
                // Features section with animations
                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(
                        icon: "arrow.right.circle.fill",
                        text: "Swipe right to keep, left to delete"
                    )
                    
                    FeatureRow(
                        icon: "calendar.circle.fill",
                        text: "Organize by year, screenshots, or random"
                    )
                    
                    FeatureRow(
                        icon: "chart.line.uptrend.xyaxis.circle.fill",
                        text: "Track your progress and save storage"
                    )
                }
                .padding(.top, 40)
                .padding(.horizontal, 40)
            
            Spacer()
            
                // Get Started button with gradient and animation
            Button(action: onContinue) {
                    HStack(spacing: 12) {
                        Text("Get Started!")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                        
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
                    .scaleEffect(animateButton ? 1.0 : 0.95)
                    .animation(.easeInOut(duration: 1.0).delay(1.0), value: animateButton)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        }
        .onAppear {
            // Start animations
            animateTitle = true
            animateFeatures = true
            animateButton = true
            animateConfetti = true
        }
    }
}



// MARK: - Confetti Piece
struct ConfettiPiece: View {
    let delay: Double
    let color: Color
    @State private var offset: CGSize = .zero
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .offset(offset)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeOut(duration: 2.0).delay(delay)) {
                    offset = CGSize(
                        width: CGFloat.random(in: -150...150),
                        height: CGFloat.random(in: -300...300)
                    )
                    rotation = Double.random(in: 0...360)
                    scale = CGFloat.random(in: 0.5...1.5)
                }
            }
    }
}

// Removed preview for production