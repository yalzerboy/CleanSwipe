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
    
    var body: some View {
        ZStack {
            // Clean background
            Color(.systemBackground)
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

    @State private var storageAvailability: StorageAvailability? = nil
    @State private var iCloudStorageStatus: ICloudStorageStatus? = nil
    @State private var storageImpactExperience: StorageImpactExperience? = nil
    @State private var loadingProgress: Double = 0.0
    
    // Track which screens we've passed for page indicator
    private var currentPageIndex: Int {
        switch currentStep {
        case .welcome: return 0
        case .benefits: return 1
        case .interactiveDemo: return 2
        case .photoCount: return 3
        case .storageAvailability: return 4
        case .iCloudStorage: return 5
        case .storageImpact: return 6
        default: return 7
        }
    }
    
    private let totalPages = 7 // welcome, benefits, interactiveDemo, photoCount, storageAvailability, iCloudStorage, storageImpact
    
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
            // Clean background
            Color(.systemBackground)
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
                                currentStep = .benefits
                            }
                        }
                        .onAppear {
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
                .foregroundColor(.primary)
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
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.5, green: 0.2, blue: 0.8))
                }
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


// MARK: - Instruction Row
struct InstructionRow: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    
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
                    .foregroundColor(.primary)
                
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
                .foregroundColor(.primary)
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
    let title: LocalizedStringKey
    let description: LocalizedStringKey
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
                    .foregroundColor(.primary)
                
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
                    .fill(Color(.secondarySystemBackground))
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
                .foregroundColor(.primary)
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
                        title: count.localizedTitle,
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
                .foregroundColor(.primary)
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
                        title: availability.localizedTitle,
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
                .foregroundColor(.primary)
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
                        title: status.localizedTitle,
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
                .foregroundColor(.primary)
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
                        title: experience.localizedTitle,
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
    let title: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
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
                .foregroundColor(.primary)
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
    @State private var isAnimating = false
    @State private var preloadedOffering: Offering? = nil
    @State private var isOfferingLoaded = false
    @State private var showingPaywall = false
    @State private var isLoadingPaywall = false  // Shows spinner when button is tapped
    @EnvironmentObject private var purchaseManager: PurchaseManager
    
    // Timeline animation states
    @State private var showLine = false
    @State private var showItem1 = false
    @State private var showItem2 = false
    @State private var showItem3 = false
    
    /// Whether the button should show loading state
    private var isLoading: Bool {
        !isOfferingLoaded || isLoadingPaywall
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    
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
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "crown.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
                    }
                    .scaleEffect(isAnimating ? 1.0 : 0.8)
                    .opacity(isAnimating ? 1.0 : 0.0)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                    
                    // Title
                    Text("Unlock Kage Premium")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .opacity(isAnimating ? 1.0 : 0.0)
                    
                    // Subtitle
                    Text("Start your free 3-day trial today")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 8)
                        .opacity(isAnimating ? 1.0 : 0.0)
                    
                    // Timeline View
                    VStack(alignment: .leading, spacing: 0) {
                        
                        // Today: Instant Access
                        TimelineRow(
                            icon: "lock.open.fill",
                            title: "Today: Instant Access",
                            description: "Unlock all premium features immediately. No payment today.",
                            isFirst: true,
                            isLast: false,
                            accentColor: Color(red: 0.5, green: 0.2, blue: 0.8),
                            showLine: showLine
                        )
                        .opacity(showItem1 ? 1.0 : 0.0)
                        .offset(x: showItem1 ? 0 : 20)
                        
                        // Day 2: Reminder
                        TimelineRow(
                            icon: "bell.badge.fill",
                            title: "Day 2: Trial Reminder",
                            description: "We'll email you a reminder before your trial ends.",
                            isFirst: false,
                            isLast: false,
                            accentColor: .gray,
                            showLine: showLine
                        )
                        .opacity(showItem2 ? 1.0 : 0.0)
                        .offset(x: showItem2 ? 0 : 20)
                        
                        // Day 3: Premium Begins
                        TimelineRow(
                            icon: "star.circle.fill",
                            title: "Day 3: Premium Begins",
                            description: "Your subscription begins. Cancel anytime before this.",
                            isFirst: false,
                            isLast: true,
                            accentColor: .gray,
                            showLine: showLine
                        )
                        .opacity(showItem3 ? 1.0 : 0.0)
                        .offset(x: showItem3 ? 0 : 20)
                        
                    }
                    .padding(.top, 40)
                    .padding(.horizontal, 32)
                    
                    // Assurance Box
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        
                        Text("No payment due now • Cancel anytime")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(20)
                    .padding(.top, 30)
                    .opacity(isAnimating ? 1.0 : 0.0)
                    
                    Spacer(minLength: 30)
                }
            }
            
            // Footer
            VStack(spacing: 0) {
                // Divider shadow
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(height: 1)
                
                VStack(spacing: 16) {
                    // Start Trial button
                    Button(action: {
                        // Show loading state immediately
                        isLoadingPaywall = true
                        // Small delay to ensure UI updates before presenting sheet
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            showingPaywall = true
                        }
                    }) {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            }
                            Text(isLoading ? "Loading..." : "Start Free Trial")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                            
                            if !isLoading {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                            }
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
                        // Pulse animation for the button
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(red: 0.5, green: 0.2, blue: 0.8).opacity(0.5), lineWidth: 2)
                                .scaleEffect(isAnimating ? 1.05 : 1.0)
                                .opacity(isAnimating ? 0.0 : 1.0)
                                .animation(Animation.easeOut(duration: 1.5).repeatForever(autoreverses: false).delay(1.0), value: isAnimating)
                        )
                    }
                    .disabled(isLoading)
                    .opacity(isLoading ? 0.7 : 1.0)
                    
                    Button(action: {
                        // Set custom attribute to track that user skipped the paywall during onboarding
                        // Wait for attribute to be set and synced before continuing
                        Task {
                            await purchaseManager.setCustomAttribute(key: "onboarding_subscription_status", value: "skipped")
                            // Small delay to ensure RevenueCat has processed the attribute
                            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                            await MainActor.run {
                                onContinue()
                            }
                        }
                    }) {
                        Text("Continue with free version")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 50)
            }
            .background(Color(.systemBackground))
            .opacity(isAnimating ? 1.0 : 0.0)
        }
        .sheet(isPresented: $showingPaywall, onDismiss: {
            // Reset loading state when sheet is dismissed
            isLoadingPaywall = false
        }) {
            if let offering = preloadedOffering {
                PaywallView(offering: offering) { success in
                    showingPaywall = false
                    if success {
                        // Set custom attribute to track that user subscribed during onboarding
                        Task {
                            await purchaseManager.setCustomAttribute(key: "onboarding_subscription_status", value: "subscribed")
                        }
                        onContinue()
                    }
                    // If not success, just close the paywall (user dismissed or cancelled)
                }
            }
        }
        .onChange(of: purchaseManager.subscriptionStatus) { newStatus in
            switch newStatus {
            case .trial, .active, .cancelled:
                onContinue()
            default:
                break
            }
        }
        .onAppear {
            // Main fade in
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }
            
            // Staggered timeline animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.4)) { showItem1 = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.5)) { showLine = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeOut(duration: 0.4)) { showItem2 = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                withAnimation(.easeOut(duration: 0.4)) { showItem3 = true }
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
            self.isOfferingLoaded = true
        }
    }
}

// MARK: - Timeline Component
struct TimelineRow: View {
    let icon: String
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let isFirst: Bool
    let isLast: Bool
    let accentColor: Color
    let showLine: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Timeline line and icon
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(accentColor)
                }
                
                if !isLast {
                    // Animated Line
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [accentColor.opacity(0.3), Color.gray.opacity(0.2)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 2)
                        .frame(height: 50) // Fixed height between items
                        .scaleEffect(y: showLine ? 1.0 : 0.0, anchor: .top)
                }
            }
            .frame(width: 32) // Fixed width for alignment
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, isLast ? 0 : 20) // Spacing for content
            }
            .padding(.top, 4) // Align text with icon top
        }
    }
}

// MARK: - Feature Checkmark
struct FeatureCheckmark: View {
    let text: LocalizedStringKey
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(Color(red: 0.5, green: 0.2, blue: 0.8))
            
            Text(text)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.primary)
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
                .foregroundColor(.primary)
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
                    title: "Safe & Reversible",
                    description: "Review selections before deletion - accidentally deleted photos are recoverable from Recently Deleted for 30 days."
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
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    
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
                    .foregroundColor(.primary)
                
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
