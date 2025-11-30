import SwiftUI
import AVKit
import RevenueCatUI
import RevenueCat
import Photos
import UserNotifications

// MARK: - Splash Screen
struct SplashView: View {
    let onComplete: () -> Void
    @State private var showResetAlert = false

    private func warmUpFrameworks() {
        // Warm up frameworks during splash screen to reduce first-use blocking
        // These operations are lightweight and won't block the UI

        // 1. Warm up Photos framework (very lightweight)
        Task.detached(priority: .background) {
            // Just check authorization status to warm up Photos framework
            let _ = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            print("🔥 [SplashView] Photos framework warmed up")
        }

        // 2. Warm up RevenueCat (already configured, just ensure it's ready)
        Task.detached(priority: .background) {
            // Small async operation to ensure RevenueCat is responsive
            if await PurchaseManager.shared.isConfigured {
                _ = await PurchaseManager.shared.checkSubscriptionStatus()
                print("🔥 [SplashView] RevenueCat warmed up")
            }
        }

        // 3. Warm up AVFoundation (very lightweight)
        Task.detached(priority: .background) {
            // Just create and immediately release AVPlayer/AVPlayerItem to warm up AVFoundation
            autoreleasepool {
                let _ = AVPlayer()
                let _ = AVPlayerItem(url: URL(string: "about:blank")!)
            }
            print("🔥 [SplashView] AVFoundation warmed up")
        }

        print("🔥 [SplashView] Framework warm-up initiated")
    }
    
    var body: some View {
        ZStack {
            // Clean white background
            Color.white
                .ignoresSafeArea()
            
            // Kage logo image
            Image("kage-text")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 250)
                .offset(x: 12, y: -25)
                .onLongPressGesture(minimumDuration: 2.0) {
                    // Debug: Reset onboarding on long press (for testing)
                    showResetAlert = true
                }
        }
        .alert("Reset Onboarding?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                UserDefaults.standard.set(false, forKey: "hasCompletedWelcomeFlow")
            }
        } message: {
            Text("This will reset the onboarding flow and permission screens. You'll see them again on next launch.")
        }
        .onAppear {
            // Use splash screen time to warm up frameworks that might block on first use
            warmUpFrameworks()

            // Show splash for 1.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                onComplete()
            }
        }
    }
}

// MARK: - Main Onboarding Flow
struct OnboardingFlowView: View {
    let onComplete: (ContentType) -> Void
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var currentStep: OnboardingStep = .welcome
    @State private var photoCount: PhotoCount? = nil
    @State private var cleaningFrequency: CleaningFrequency? = nil
    @State private var storageAvailability: StorageAvailability? = nil
    @State private var iCloudStorageStatus: ICloudStorageStatus? = nil
    @State private var storageImpactExperience: StorageImpactExperience? = nil
    @State private var loadingProgress: Double = 0.0
    
    // Track which screens we've passed for page indicator
    private var currentPageIndex: Int {
        switch currentStep {
        case .welcome: return 0
        case .howTo: return 1
        case .benefits: return 2
        case .interactiveDemo: return 3
        case .photoCount: return 4
        case .cleaningFrequency: return 5
        case .storageAvailability: return 6
        case .iCloudStorage: return 7
        case .storageImpact: return 8
        default: return 9
        }
    }
    
    private let totalPages = 9 // welcome, howTo, benefits, interactiveDemo, photoCount, cleaningFrequency, storageAvailability, iCloudStorage, storageImpact
    
    private var hasPremiumAccess: Bool {
        switch purchaseManager.subscriptionStatus {
        case .trial, .active, .cancelled:
            return true
        case .notSubscribed, .expired:
            return false
        }
    }
    
    var body: some View {
        ZStack {
            // Clean white background
            Color.white
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Page Indicator at top
                if currentPageIndex < totalPages {
                    PageIndicator(currentPage: currentPageIndex, totalPages: totalPages)
                        .padding(.top, 60)
                        .padding(.bottom, 20)
                }
                
                // Content
                Group {
                    switch currentStep {
                    case .welcome:
                        WelcomeView {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentStep = .howTo
                            }
                        }
                        .onAppear {
                        }
            case .howTo:
                HowToView {
                            withAnimation(.easeInOut(duration: 0.3)) {
                    currentStep = .benefits
                            }
                }
            case .benefits:
                BenefitsView {
                            withAnimation(.easeInOut(duration: 0.3)) {
                    currentStep = .interactiveDemo
                            }
                }
            case .interactiveDemo:
                InteractiveSwipeDemoView {
                            withAnimation(.easeInOut(duration: 0.3)) {
                    currentStep = .photoCount
                            }
                }
            case .photoCount:
                PhotoCountView(selectedCount: $photoCount) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                        currentStep = .cleaningFrequency
                            }
                }
            case .cleaningFrequency:
                CleaningFrequencyView(selectedFrequency: $cleaningFrequency) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                        currentStep = .storageAvailability
                    }
                }
            case .storageAvailability:
                StorageAvailabilityView(selectedAvailability: $storageAvailability) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentStep = .iCloudStorage
                    }
                }
            case .iCloudStorage:
                ICloudStorageStatusView(selectedStatus: $iCloudStorageStatus) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentStep = .storageImpact
                    }
                }
            case .storageImpact:
                StorageImpactExperienceView(selectedExperience: $storageImpactExperience) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentStep = .preparing
                    }
                }
            case .preparing:
                PreparingView(progress: $loadingProgress) {
                    currentStep = hasPremiumAccess ? .permissions : .freeTrialIntro
                }
            case .freeTrialIntro:
                FreeTrialIntroView {
                    currentStep = .permissions
                }
            case .permissions:
                PermissionsView {
                            // Complete onboarding and go to app
                            onComplete(.photos)
                        }
                    default:
                        EmptyView()
                    }
                }
            }
        }
    }
}

// MARK: - Page Indicator
struct PageIndicator: View {
    let currentPage: Int
    let totalPages: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? 
                          Color(red: 0.5, green: 0.2, blue: 0.8) : // Purple for current
                          Color.gray.opacity(0.3)) // Gray for others
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.3), value: currentPage)
            }
        }
    }
}

// MARK: - Welcome View
struct WelcomeView: View {
    let onContinue: () -> Void
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 0) {
                Spacer()
                
            // App icon or illustration
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.5, green: 0.2, blue: 0.8).opacity(0.2),
                                Color(red: 0.6, green: 0.3, blue: 0.9).opacity(0.1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 60, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.5, green: 0.2, blue: 0.8),
                                Color(red: 0.6, green: 0.3, blue: 0.9)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(isAnimating ? 1.0 : 0.8)
                .opacity(isAnimating ? 1.0 : 0.0)
            .padding(.bottom, 40)
            
            // Title
            Text("Welcome to Kage")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .opacity(isAnimating ? 1.0 : 0.0)
            
            // Subtitle
            Text("Organize your photos in minutes,\nnot hours")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 16)
                    .opacity(isAnimating ? 1.0 : 0.0)
            
            // Rating badge
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(red: 0.5, green: 0.2, blue: 0.8))
                    }
                }
                
                Text("4.9 • Trusted by 50,000+ users")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(.top, 24)
            .opacity(isAnimating ? 1.0 : 0.0)
            
            Spacer()
            
            // Continue button
                Button(action: onContinue) {
                Text("Get Started")
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
                .opacity(isAnimating ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
        isAnimating = true
            }
        }
    }
}

// MARK: - How To View
struct HowToView: View {
    let onContinue: () -> Void
    @State private var isAnimating = false
    
    var body: some View {
            VStack(spacing: 0) {
            Spacer()
            
            // Title
            Text("Simple & Intuitive")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
                .opacity(isAnimating ? 1.0 : 0.0)
            
            // Instructions
            VStack(spacing: 36) {
                InstructionRow(
                    icon: "arrow.left.circle.fill",
                    iconColor: Color(red: 0.95, green: 0.3, blue: 0.3),
                        title: "Swipe Left",
                    description: "Mark photos for deletion"
                )
                .opacity(isAnimating ? 1.0 : 0.0)
                .offset(x: isAnimating ? 0 : -20)
                
                InstructionRow(
                    icon: "arrow.right.circle.fill",
                    iconColor: Color(red: 0.2, green: 0.7, blue: 0.4),
                        title: "Swipe Right",
                    description: "Keep your favorites"
                )
                .opacity(isAnimating ? 1.0 : 0.0)
                .offset(x: isAnimating ? 0 : 20)
                
                InstructionRow(
                    icon: "checkmark.shield.fill",
                    iconColor: Color(red: 0.5, green: 0.2, blue: 0.8),
                    title: "Review & Confirm",
                    description: "Final review before any deletion"
                )
                .opacity(isAnimating ? 1.0 : 0.0)
            }
            .padding(.horizontal, 40)
            
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
            .opacity(isAnimating ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Instruction Row
struct InstructionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 20) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 56, height: 56)
                
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
                
                Text(description)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
    }
}

// MARK: - Benefits View
struct BenefitsView: View {
    let onContinue: () -> Void
    @State private var isAnimating = false
    
    var body: some View {
            VStack(spacing: 0) {
            Spacer()
            
            // Title
            Text("Why You'll Love It")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
                .opacity(isAnimating ? 1.0 : 0.0)
            
            // Benefits
            VStack(spacing: 32) {
                BenefitCard(
                    icon: "icloud.fill",
                    title: "Free Up Storage",
                    description: "Reclaim gigabytes of space on your device",
                    accentColor: Color(red: 0.3, green: 0.6, blue: 1.0)
                )
                .opacity(isAnimating ? 1.0 : 0.0)
                .offset(y: isAnimating ? 0 : 20)
                
                BenefitCard(
                    icon: "clock.fill",
                    title: "Save Time",
                    description: "Organize thousands of photos in minutes",
                    accentColor: Color(red: 0.5, green: 0.2, blue: 0.8)
                )
                .opacity(isAnimating ? 1.0 : 0.0)
                .offset(y: isAnimating ? 0 : 20)
                
                BenefitCard(
                    icon: "heart.fill",
                    title: "Rediscover Memories",
                    description: "See your best photos as you organize",
                    accentColor: Color(red: 0.95, green: 0.3, blue: 0.3)
                )
                .opacity(isAnimating ? 1.0 : 0.0)
                .offset(y: isAnimating ? 0 : 20)
            }
                .padding(.horizontal, 40)
            
            Spacer()
            
            // Continue button
                Button(action: onContinue) {
                Text("Try It Now")
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
            .opacity(isAnimating ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Benefit Card
struct BenefitCard: View {
    let icon: String
    let title: String
    let description: String
    let accentColor: Color
    
    var body: some View {
            HStack(spacing: 16) {
            // Icon
                ZStack {
                        Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(accentColor)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.black)
                
                Text(description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
                
                Spacer()
            }
        .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.05))
        )
    }
}

// MARK: - Photo Count View
struct PhotoCountView: View {
    @Binding var selectedCount: PhotoCount?
    let onSelection: () -> Void
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Icon
        ZStack {
                Circle()
                    .fill(
            LinearGradient(
                gradient: Gradient(colors: [
                                Color(red: 0.5, green: 0.2, blue: 0.8).opacity(0.2),
                                Color(red: 0.6, green: 0.3, blue: 0.9).opacity(0.1)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 45, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.5, green: 0.2, blue: 0.8),
                                Color(red: 0.6, green: 0.3, blue: 0.9)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(isAnimating ? 1.0 : 0.8)
            .opacity(isAnimating ? 1.0 : 0.0)
            .padding(.bottom, 40)
            
            // Title
            Text("How many photos do you have?")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .padding(.bottom, 8)
                .opacity(isAnimating ? 1.0 : 0.0)
            
            // Subtitle
            Text("This will help personalise your app experience")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .opacity(isAnimating ? 1.0 : 0.0)
                
            // Options
                VStack(spacing: 12) {
                ForEach(PhotoCount.allCases, id: \.self) { count in
                    OptionButton(
                        title: count.rawValue,
                        isSelected: selectedCount == count
                    ) {
                        selectedCount = count
                        proceedToNext()
                    }
                    .opacity(isAnimating ? 1.0 : 0.0)
                }
            }
            .padding(.horizontal, 40)
                
                Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }
        }
    }
    
    private func proceedToNext() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onSelection()
        }
    }
}

// MARK: - Cleaning Frequency View
struct CleaningFrequencyView: View {
    @Binding var selectedFrequency: CleaningFrequency?
    let onSelection: () -> Void
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Icon
        ZStack {
                Circle()
                    .fill(
            LinearGradient(
                gradient: Gradient(colors: [
                                Color(red: 0.5, green: 0.2, blue: 0.8).opacity(0.2),
                                Color(red: 0.6, green: 0.3, blue: 0.9).opacity(0.1)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 45, weight: .medium))
                    .foregroundStyle(
            LinearGradient(
                gradient: Gradient(colors: [
                                Color(red: 0.5, green: 0.2, blue: 0.8),
                                Color(red: 0.6, green: 0.3, blue: 0.9)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                    )
            }
            .scaleEffect(isAnimating ? 1.0 : 0.8)
            .opacity(isAnimating ? 1.0 : 0.0)
            .padding(.bottom, 40)
            
            // Title
            Text("How often do you clean your camera roll?")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .padding(.bottom, 8)
                .opacity(isAnimating ? 1.0 : 0.0)
            
            // Subtitle
            Text("This will help personalise your app experience")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .opacity(isAnimating ? 1.0 : 0.0)
                
            // Options
                VStack(spacing: 12) {
                ForEach(CleaningFrequency.allCases, id: \.self) { frequency in
                    OptionButton(
                        title: frequency.rawValue,
                        isSelected: selectedFrequency == frequency
                    ) {
                        selectedFrequency = frequency
                        proceedToNext()
                    }
                    .opacity(isAnimating ? 1.0 : 0.0)
                }
            }
            .padding(.horizontal, 40)
                
                Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }
        }
    }
    
    private func proceedToNext() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onSelection()
        }
    }
}

// MARK: - Storage Availability View
struct StorageAvailabilityView: View {
    @Binding var selectedAvailability: StorageAvailability?
    let onSelection: () -> Void
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.5, green: 0.2, blue: 0.8).opacity(0.2),
                                Color(red: 0.6, green: 0.3, blue: 0.9).opacity(0.1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "internaldrive")
                    .font(.system(size: 45, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.5, green: 0.2, blue: 0.8),
                                Color(red: 0.6, green: 0.3, blue: 0.9)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(isAnimating ? 1.0 : 0.8)
            .opacity(isAnimating ? 1.0 : 0.0)
            .padding(.bottom, 40)
            
            Text("How much free storage do you have?")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .padding(.bottom, 8)
                .opacity(isAnimating ? 1.0 : 0.0)
            
            Text("This will help personalise your app experience")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .opacity(isAnimating ? 1.0 : 0.0)
            
            VStack(spacing: 12) {
                ForEach(StorageAvailability.allCases, id: \.self) { availability in
                    OptionButton(
                        title: availability.rawValue,
                        isSelected: selectedAvailability == availability
                    ) {
                        selectedAvailability = availability
                        proceedToNext()
                    }
                    .opacity(isAnimating ? 1.0 : 0.0)
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }
        }
    }
    
    private func proceedToNext() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onSelection()
        }
    }
}

// MARK: - iCloud Storage Status View
struct ICloudStorageStatusView: View {
    @Binding var selectedStatus: ICloudStorageStatus?
    let onSelection: () -> Void
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.5, green: 0.2, blue: 0.8).opacity(0.2),
                                Color(red: 0.6, green: 0.3, blue: 0.9).opacity(0.1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "icloud")
                    .font(.system(size: 45, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.5, green: 0.2, blue: 0.8),
                                Color(red: 0.6, green: 0.3, blue: 0.9)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(isAnimating ? 1.0 : 0.8)
            .opacity(isAnimating ? 1.0 : 0.0)
            .padding(.bottom, 40)
            
            Text("Do you pay for iCloud storage?")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .padding(.bottom, 8)
                .opacity(isAnimating ? 1.0 : 0.0)
            
            Text("This will help personalise your app experience")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .opacity(isAnimating ? 1.0 : 0.0)
            
            VStack(spacing: 12) {
                ForEach(ICloudStorageStatus.allCases, id: \.self) { status in
                    OptionButton(
                        title: status.rawValue,
                        isSelected: selectedStatus == status
                    ) {
                        selectedStatus = status
                        proceedToNext()
                    }
                    .opacity(isAnimating ? 1.0 : 0.0)
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }
        }
    }
    
    private func proceedToNext() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onSelection()
        }
    }
}

// MARK: - Storage Impact Experience View
struct StorageImpactExperienceView: View {
    @Binding var selectedExperience: StorageImpactExperience?
    let onSelection: () -> Void
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.5, green: 0.2, blue: 0.8).opacity(0.2),
                                Color(red: 0.6, green: 0.3, blue: 0.9).opacity(0.1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "photo.stack")
                    .font(.system(size: 45, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.5, green: 0.2, blue: 0.8),
                                Color(red: 0.6, green: 0.3, blue: 0.9)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(isAnimating ? 1.0 : 0.8)
            .opacity(isAnimating ? 1.0 : 0.0)
            .padding(.bottom, 40)
            
            Text("Have you recently been unable to take photos or videos due to low storage?")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .padding(.bottom, 8)
                .opacity(isAnimating ? 1.0 : 0.0)
            
            Text("This will help personalise your app experience")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .opacity(isAnimating ? 1.0 : 0.0)
            
            VStack(spacing: 12) {
                ForEach(StorageImpactExperience.allCases, id: \.self) { experience in
                    OptionButton(
                        title: experience.rawValue,
                        isSelected: selectedExperience == experience
                    ) {
                        selectedExperience = experience
                        proceedToNext()
                    }
                    .opacity(isAnimating ? 1.0 : 0.0)
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }
        }
    }
    
    private func proceedToNext() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onSelection()
        }
    }
}

// MARK: - Option Button
struct OptionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? .white : .black)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                    .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? 
                          LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.5, green: 0.2, blue: 0.8),
                                Color(red: 0.6, green: 0.3, blue: 0.9)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                          ) :
                          LinearGradient(
                            gradient: Gradient(colors: [
                                Color.gray.opacity(0.1),
                                Color.gray.opacity(0.1)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                          )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

// MARK: - Preparing View
struct PreparingView: View {
    @Binding var progress: Double
    let onComplete: () -> Void
    @State private var isAnimating = false
    @State private var currentFeature = 0
    @EnvironmentObject private var purchaseManager: PurchaseManager
    
    private let features = [
        "Loading your photo library",
        "Setting up smart filters",
        "Preparing batch processing",
        "Optimizing performance",
        "Almost ready"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Animated icon
        ZStack {
                Circle()
                    .fill(
            LinearGradient(
                gradient: Gradient(colors: [
                                Color(red: 0.5, green: 0.2, blue: 0.8).opacity(0.2),
                                Color(red: 0.6, green: 0.3, blue: 0.9).opacity(0.1)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                    )
                            .frame(width: 120, height: 120)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 50, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.5, green: 0.2, blue: 0.8),
                                Color(red: 0.6, green: 0.3, blue: 0.9)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(.linear(duration: 3).repeatForever(autoreverses: false), value: isAnimating)
            }
            .padding(.bottom, 40)
            
            // Title
            Text("Preparing Your Experience")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 8)
            
            // Feature loading text
            Text(features[currentFeature])
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .animation(.easeInOut(duration: 0.3), value: currentFeature)
                        
                        // Progress bar
            VStack(spacing: 12) {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle(tint: Color(red: 0.5, green: 0.2, blue: 0.8)))
                    .scaleEffect(y: 2)
                
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(red: 0.5, green: 0.2, blue: 0.8))
            }
            .padding(.horizontal, 60)
            
            Spacer()
            Spacer()
        }
        .onAppear {
            isAnimating = true
            startLoadingAnimation()
            // Preload paywall offering early if user doesn't have premium access
            // This ensures the paywall appears instantly when they reach the free trial intro page
            let needsPaywall = !(purchaseManager.subscriptionStatus == .trial || 
                                 purchaseManager.subscriptionStatus == .active || 
                                 purchaseManager.subscriptionStatus == .cancelled)
            if needsPaywall {
                Task {
                    // Preload in the background - don't await, just start it
                    _ = await purchaseManager.getOffering(forPlacement: PurchaseManager.PlacementIdentifier.homePostOnboarding.rawValue)
                }
            }
        }
    }
    
    private func startLoadingAnimation() {
        // Animate progress
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            if progress < 1.0 {
                progress += 0.02
                
                // Update feature text based on progress
                let featureIndex = Int(progress * Double(features.count))
                if featureIndex < features.count && featureIndex != currentFeature {
                    currentFeature = featureIndex
                }
            } else {
                timer.invalidate()
                // Wait a moment then continue
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onComplete()
                }
            }
        }
    }
}

// MARK: - Free Trial Intro View (Paywall)
struct FreeTrialIntroView: View {
    let onContinue: () -> Void
    @State private var paywallTrigger = 0
    @State private var isAnimating = false
    @State private var preloadedOffering: Offering? = nil
    @EnvironmentObject private var purchaseManager: PurchaseManager
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Icon
        ZStack {
                Circle()
                    .fill(
            LinearGradient(
                gradient: Gradient(colors: [
                                Color(red: 0.5, green: 0.2, blue: 0.8).opacity(0.2),
                                Color(red: 0.6, green: 0.3, blue: 0.9).opacity(0.1)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "crown.fill")
                    .font(.system(size: 45, weight: .medium))
                    .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
            }
            .scaleEffect(isAnimating ? 1.0 : 0.8)
            .opacity(isAnimating ? 1.0 : 0.0)
            .padding(.bottom, 40)
            
            // Title
            Text("Unlock Kage Premium")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .opacity(isAnimating ? 1.0 : 0.0)
            
            // Subtitle
            Text("Start your free trial today")
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 16)
                .opacity(isAnimating ? 1.0 : 0.0)
            
            // Features
            VStack(spacing: 20) {
                FeatureCheckmark(text: "Unlimited photo organization")
                FeatureCheckmark(text: "No advertisements for life")
                FeatureCheckmark(text: "All advanced filters")
                FeatureCheckmark(text: "Smart AI cleanup")
                }
                .padding(.top, 40)
            .padding(.horizontal, 40)
            .opacity(isAnimating ? 1.0 : 0.0)
            
            Spacer()
            
            // Start Trial button
                Button(action: {
                    paywallTrigger += 1
                }) {
                HStack(spacing: 8) {
                    Text("Start Free Trial")
                        .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                    
                        Image(systemName: "crown.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
                    }
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

                Button(action: {
                    // Set custom attribute to track that user skipped the paywall during onboarding
                    Task {
                        await purchaseManager.setCustomAttribute(key: "onboarding_subscription_status", value: "skipped")
                    }
                    onContinue()
                }) {
                Text("Continue with free version")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(.top, 16)
            .padding(.bottom, 50)
            .opacity(isAnimating ? 1.0 : 0.0)
        }
        .presentPaywallIfNeeded(
            requiredEntitlementIdentifier: "Premium",
            offering: preloadedOffering,
            purchaseCompleted: { customerInfo in
                // Set custom attribute to track that user subscribed during onboarding
                Task {
                    // Check if they're on trial or active subscription
                    if let entitlement = customerInfo.entitlements["Premium"], entitlement.isActive {
                        let attributeValue = entitlement.periodType == .trial ? "trial_started" : "subscribed"
                        await purchaseManager.setCustomAttribute(key: "onboarding_subscription_status", value: attributeValue)
                    } else {
                        await purchaseManager.setCustomAttribute(key: "onboarding_subscription_status", value: "subscribed")
                    }
                }
                onContinue()
            },
            restoreCompleted: { customerInfo in
                // If they restore, they likely had a subscription before, so mark as subscribed
                Task {
                    await purchaseManager.setCustomAttribute(key: "onboarding_subscription_status", value: "restored")
                }
                onContinue()
            }
        )
        .id(paywallTrigger)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }
            // Preload the offering so paywall appears instantly when button is tapped
            Task {
                await preloadOffering()
            }
        }
    }
    
    private func preloadOffering() async {
        // Preload the offering for the onboarding placement, or fall back to default
        let offering = await purchaseManager.getOffering(forPlacement: PurchaseManager.PlacementIdentifier.homePostOnboarding.rawValue)
        await MainActor.run {
            self.preloadedOffering = offering
        }
    }
}

// MARK: - Feature Checkmark
struct FeatureCheckmark: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(Color(red: 0.5, green: 0.2, blue: 0.8))
            
            Text(text)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.black)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
}

// MARK: - Permissions View (Info screens AND actual permission requests)
struct PermissionsView: View {
    let onContinue: () -> Void
    @State private var showingPhotoPermission = false
    @State private var showingNotificationPermission = false
    
    var body: some View {
        Group {
            if !showingPhotoPermission && !showingNotificationPermission {
                // First show the info screen
                PermissionsIntroView {
                    // After info screen, show photo permission
                    showingPhotoPermission = true
                }
                .onAppear {
                }
            } else if showingPhotoPermission && !showingNotificationPermission {
                // Show photo permission screen
                PhotoAccessView {
                    // After photo permission, show notification permission
                    showingPhotoPermission = false
                    showingNotificationPermission = true
                }
                .onAppear {
                }
            } else if showingNotificationPermission {
                // Show notification permission screen
                NotificationPermissionView {
                    // All done, complete onboarding
                    onContinue()
                }
                .onAppear {
                }
            }
        }
    }
}

// MARK: - Permissions Intro View
struct PermissionsIntroView: View {
    let onContinue: () -> Void
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Icon
        ZStack {
                Circle()
                    .fill(
            LinearGradient(
                gradient: Gradient(colors: [
                                Color(red: 0.5, green: 0.2, blue: 0.8).opacity(0.2),
                                Color(red: 0.6, green: 0.3, blue: 0.9).opacity(0.1)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 45, weight: .medium))
                    .foregroundStyle(
            LinearGradient(
                gradient: Gradient(colors: [
                                Color(red: 0.5, green: 0.2, blue: 0.8),
                                Color(red: 0.6, green: 0.3, blue: 0.9)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
                    )
            }
            .scaleEffect(isAnimating ? 1.0 : 0.8)
            .opacity(isAnimating ? 1.0 : 0.0)
            .padding(.bottom, 40)
            
            // Title
            Text("Your Privacy Matters")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.black)
                            .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .opacity(isAnimating ? 1.0 : 0.0)
            
            // Subtitle
            Text("Kage needs a few permissions to work its magic")
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                .padding(.top, 16)
                .opacity(isAnimating ? 1.0 : 0.0)
                    
            // Privacy features
                    VStack(spacing: 24) {
                PrivacyFeature(
                    icon: "iphone.and.arrow.forward",
                    title: "Never Leaves Your Phone",
                    description: "All photos stay on your device. Nothing is uploaded to the cloud."
                )

                PrivacyFeature(
                    icon: "checkmark.shield.fill",
                    title: "You're In Control",
                    description: "Review and confirm every deletion before it happens."
                    )
                }
                .padding(.top, 40)
                .padding(.horizontal, 40)
            .opacity(isAnimating ? 1.0 : 0.0)
            
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
            .opacity(isAnimating ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Privacy Feature
struct PrivacyFeature: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                    Circle()
                    .fill(Color(red: 0.5, green: 0.2, blue: 0.8).opacity(0.15))
                    .frame(width: 50, height: 50)
                    
                    Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Color(red: 0.5, green: 0.2, blue: 0.8))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                
                Text(description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
}

// MARK: - Final Continue View (Unused for now, kept for potential future use)
struct FinalContinueView: View {
    let onSkip: () -> Void
    let onContinue: () -> Void
    
    var body: some View {
        VStack {
            Text("Final Continue")
            Button("Continue", action: onContinue)
        }
    }
}

// MARK: - Onboarding Steps
// Note: Enums moved to Models/ContentType.swift

#Preview {
    OnboardingFlowView { _ in
    }
}
