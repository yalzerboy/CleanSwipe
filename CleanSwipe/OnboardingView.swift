import SwiftUI
import AVKit

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
    @State private var photoCount: PhotoCount = .less500
    @State private var cleaningFrequency: CleaningFrequency = .never
    @State private var contentType: ContentType = .photos
    @State private var loadingProgress: Double = 0.0
    
    var body: some View {
        ZStack {
            // Baby blue background for all slides
            Color(red: 0.7, green: 0.85, blue: 1.0)
                .ignoresSafeArea()
            
            switch currentStep {
            case .welcome:
                WelcomeView {
                    currentStep = .howTo
                }
            case .howTo:
                HowToView {
                    currentStep = .benefits
                }
            case .benefits:
                BenefitsView {
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
                    currentStep = .preparing
                }
            case .preparing:
                PreparingView(progress: $loadingProgress) {
                    currentStep = .freeTrialIntro
                }
            case .freeTrialIntro:
                FreeTrialIntroView {
                    currentStep = .trialDetails
                }
            case .trialDetails:
                TrialDetailsView {
                    currentStep = .finalContinue
                }
            case .finalContinue:
                FinalContinueView(onSkip: { onComplete(contentType) }, onContinue: { onComplete(contentType) })
            }
        }
    }
}

// MARK: - Onboarding Steps
// Note: Enums moved to Models/ContentType.swift

// MARK: - Welcome View (Current video onboarding)
struct WelcomeView: View {
    let onContinue: () -> Void
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            // Video Player
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        player.actionAtItemEnd = .none
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
                    .overlay {
                        LinearGradient(
                            gradient: Gradient(colors: [.black.opacity(0.2), .black.opacity(0.4)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
            
            VStack(spacing: 30) {
                Spacer()
                
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
                
                Button(action: onContinue) {
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
    }
    
    private func setupPlayer() {
        guard let url = Bundle.main.url(forResource: "onboarding_video", withExtension: "mp4") else {
            return
        }
        
        let player = AVPlayer(url: url)
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

// MARK: - How To View
struct HowToView: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 20) {
                Text("Quick How-To")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                VStack(spacing: 30) {
                    HStack(spacing: 20) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 24))
                            .foregroundColor(.red)
                        Text("Swipe left to delete")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    HStack(spacing: 20) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 24))
                            .foregroundColor(.green)
                        Text("Swipe right to keep")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .padding(.vertical, 30)
            }
            
            Text("De-clutter your phone in one clean swipe!")
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .padding(.top, 80)
    }
}

// MARK: - Benefits View
struct BenefitsView: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 20) {
                Text("Enjoy the Free Space")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("No more \"out of storage\"")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            VStack(spacing: 20) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text("Free up space on your device and keep your favorite memories")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .padding(.top, 80)
    }
}

// MARK: - Age View
struct AgeView: View {
    @Binding var selectedAge: String
    let onContinue: () -> Void
    
    private let ageRanges = ["Under 18", "18-24", "25-34", "35-44", "45-54", "55-64", "65+"]
    
    var body: some View {
        VStack(spacing: 40) {
            Text("What's your age?")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            VStack(spacing: 16) {
                ForEach(ageRanges, id: \.self) { age in
                    Button(action: {
                        selectedAge = age
                    }) {
                        HStack {
                            Image(systemName: selectedAge == age ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundColor(selectedAge == age ? .blue : .gray)
                            
                            Text(age)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedAge == age ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                        )
                    }
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            HStack(spacing: 20) {
                Button("Skip") {
                    onContinue()
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                
                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .padding(.top, 80)
    }
}

// MARK: - Photo Count View
struct PhotoCountView: View {
    @Binding var selectedCount: PhotoCount
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            Text("How many photos do you have?")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 16) {
                ForEach(PhotoCount.allCases, id: \.self) { count in
                    Button(action: {
                        selectedCount = count
                    }) {
                        HStack {
                            Image(systemName: selectedCount == count ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundColor(selectedCount == count ? .blue : .gray)
                            
                            Text(count.rawValue)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedCount == count ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                        )
                    }
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            HStack(spacing: 20) {
                Button("Skip") {
                    onContinue()
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                
                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .padding(.top, 80)
    }
}

// MARK: - Cleaning Frequency View
struct CleaningFrequencyView: View {
    @Binding var selectedFrequency: CleaningFrequency
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            Text("How often do you clean your camera roll?")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 16) {
                ForEach(CleaningFrequency.allCases, id: \.self) { frequency in
                    Button(action: {
                        selectedFrequency = frequency
                    }) {
                        HStack {
                            Image(systemName: selectedFrequency == frequency ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundColor(selectedFrequency == frequency ? .blue : .gray)
                            
                            Text(frequency.rawValue)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedFrequency == frequency ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                        )
                    }
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            HStack(spacing: 20) {
                Button("Skip") {
                    onContinue()
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                
                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .padding(.top, 80)
    }
}

// MARK: - Content Type View
struct ContentTypeView: View {
    @Binding var selectedType: ContentType
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            Text("Do you want to clean up photos or photos & videos?")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 20) {
                ForEach(ContentType.allCases, id: \.self) { type in
                    Button(action: {
                        selectedType = type
                    }) {
                        Text(type.rawValue)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedType == type ? Color.blue : Color.gray.opacity(0.3))
                            )
                    }
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .padding(.top, 80)
    }
}

// MARK: - Preparing View
struct PreparingView: View {
    @Binding var progress: Double
    let onComplete: () -> Void
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 40) {
            Text("Thanks! Preparing your experience now")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 20) {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .frame(height: 8)
                    .padding(.horizontal, 40)
                
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
        }
        .padding(.top, 150)
        .onAppear {
            startProgress()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startProgress() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            if progress < 1.0 {
                progress += 0.017 // Completes in ~3 seconds
            } else {
                timer?.invalidate()
                onComplete()
            }
        }
    }
}

// MARK: - Free Trial Intro View
struct FreeTrialIntroView: View {
    let onContinue: () -> Void
    @State private var player: AVPlayer?
    
    var body: some View {
        VStack(spacing: 40) {
            Text("We want you to use CleanSwipe for free")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            // Video player placeholder
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.3))
                .frame(height: 200)
                .overlay(
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.7))
                )
                .padding(.horizontal, 40)
            
            Text("No payment due now")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
            
            Button(action: onContinue) {
                Text("Try for Free")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .padding(.top, 80)
    }
}

// MARK: - Trial Details View
struct TrialDetailsView: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            Text("How does your free trial work?")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.blue)
                    
                    Text("Unlimited swipes, all groups unlocked, no adverts")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.9))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("In 3 days - free trial ends")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.blue)
                    
                    Text("You will not be charged before, you can cancel at any time")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .padding(.top, 80)
    }
}

// MARK: - Final Continue View
struct FinalContinueView: View {
    let onSkip: () -> Void
    let onContinue: () -> Void
    
    @StateObject private var purchaseManager = PurchaseManager.shared
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(spacing: 40) {
            HStack {
                Button(action: onSkip) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            VStack(spacing: 30) {
                Text("Tap continue to start cleaning up your phone and keep those memories alive")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        Text("•")
                            .foregroundColor(.blue)
                        Text("Make cleaning up storage fun and quick, at any time!")
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    HStack(alignment: .top) {
                        Text("•")
                            .foregroundColor(.blue)
                        Text("3 days free, then just £1/week for a premium experience")
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    HStack(alignment: .top) {
                        Text("•")
                            .foregroundColor(.blue)
                        Text("No payment now")
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .font(.system(size: 16))
                .padding(.horizontal, 40)
            }
            
            Spacer()
            
            VStack(spacing: 16) {
                Button(action: {
                    Task {
                        await handleRestorePurchases()
                    }
                }) {
                    HStack {
                        if case .restoring = purchaseManager.purchaseState {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        
                        Text("Restore Purchases")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .disabled(purchaseManager.purchaseState == .restoring || purchaseManager.purchaseState == .purchasing)
                
                Button(action: {
                    Task {
                        await handleStartTrial()
                    }
                }) {
                    HStack {
                        if case .purchasing = purchaseManager.purchaseState {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        
                        Text(purchaseButtonText)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(purchaseButtonColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(purchaseManager.purchaseState == .purchasing || purchaseManager.purchaseState == .restoring)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .onChange(of: purchaseManager.purchaseState) { state in
            handlePurchaseStateChange(state)
        }
        .alert("Purchase Status", isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }
    
    private var purchaseButtonText: String {
        switch purchaseManager.purchaseState {
        case .purchasing:
            return "Starting Trial..."
        case .restoring:
            return "Continue"
        case .success:
            return "Continue"
        default:
            return "Start Free Trial"
        }
    }
    
    private var purchaseButtonColor: Color {
        switch purchaseManager.purchaseState {
        case .purchasing, .restoring:
            return Color.blue.opacity(0.7)
        default:
            return Color.blue
        }
    }
    
    private func handleStartTrial() async {
        await purchaseManager.startTrialPurchase()
    }
    
    private func handleRestorePurchases() async {
        await purchaseManager.restorePurchases()
    }
    
    private func handlePurchaseStateChange(_ state: PurchaseState) {
        switch state {
        case .success:
            // Check if trial was successfully started
            if purchaseManager.subscriptionStatus == .trial {
                alertMessage = "Welcome to your 3-day free trial! Enjoy unlimited access to CleanSwipe Premium."
                showingAlert = true
                
                // Proceed to main app after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    onContinue()
                }
            } else {
                onContinue()
            }
            
        case .failed(let error):
            if let purchaseError = error as? PurchaseError {
                switch purchaseError {
                case .userCancelled:
                    // Don't show alert for user cancellation
                    break
                default:
                    alertMessage = purchaseError.localizedDescription
                    showingAlert = true
                }
            } else {
                alertMessage = "Purchase failed: \(error.localizedDescription)"
                showingAlert = true
            }
            
        default:
            break
        }
    }
}

#Preview {
    OnboardingFlowView { contentType in
        print("Onboarding completed with content type: \(contentType)")
    }
} 