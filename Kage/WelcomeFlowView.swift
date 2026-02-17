import SwiftUI
import Photos
import UserNotifications

// MARK: - Welcome Flow View
struct WelcomeFlowView: View {
    let onComplete: () -> Void
    @State private var currentStep: WelcomeStep = .photoAccess
    @State private var isCheckingPermissions = true
    
    var body: some View {
        ZStack {
            // Clean white background
            Color(.systemBackground)
                .ignoresSafeArea()
            
            if isCheckingPermissions {
                // Loading indicator while checking permissions
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.5, green: 0.2, blue: 0.8)))
                        .scaleEffect(1.5)
                    
                    Text("Checking permissions...")
                        .font(.system(size: min(17, UIScreen.main.bounds.width * 0.045), weight: .medium))
                        .foregroundColor(.gray)
                        .padding(.top, 20)
                }
            } else {
                switch currentStep {
                case .photoAccess:
                    PhotoAccessView {
                        checkAndProceedToNextStep()
                    }
                case .notifications:
                    NotificationPermissionView {
                        onComplete()
                    }
                }
            }
        }
        .onAppear {
            checkInitialPermissions()
        }
    }
    
    private func checkInitialPermissions() {
        Task {
            await checkPermissionsAndSetInitialStep()
        }
    }
    
    private func checkPermissionsAndSetInitialStep() async {
        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        let notificationStatus = notificationSettings.authorizationStatus
        
        await MainActor.run {
            // Photo access is REQUIRED - always check photo access first
            if photoStatus == .denied || photoStatus == .restricted || photoStatus == .notDetermined {
                // Photo access denied or not determined - MUST show photo access screen
                currentStep = .photoAccess
            } else if photoStatus == .authorized || photoStatus == .limited {
                // Photo access granted, check notifications
                if notificationStatus == .authorized {
                    // Both permissions granted, complete flow
                    onComplete()
                } else {
                    // Only notification permission needed
                    currentStep = .notifications
                }
            } else {
                // Default to photo access screen
                currentStep = .photoAccess
            }
            
            isCheckingPermissions = false
        }
    }
    
    private func checkAndProceedToNextStep() {
        Task {
            await MainActor.run {
                // ALWAYS show notification permission screen (don't skip it)
                // Even if already granted, let user see the screen
                currentStep = .notifications
            }
        }
    }
}

// MARK: - Welcome Steps
// Note: Enum moved to Models/ContentType.swift

// MARK: - Photo Access View
struct PhotoAccessView: View {
    let onContinue: () -> Void
    @State private var isRequestingPermission = false
    @State private var photoAccessStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
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
                
                Image(systemName: "photo.on.rectangle")
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
            Text("Photo Library Access")
                .font(.system(size: min(32, UIScreen.main.bounds.width * 0.08), weight: .bold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .opacity(isAnimating ? 1.0 : 0.0)

            // Subtitle
            Text("We need access to help you organize your photos")
                .font(.system(size: min(17, UIScreen.main.bounds.width * 0.045), weight: .regular))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 16)
                .opacity(isAnimating ? 1.0 : 0.0)
            
            // Features
            VStack(spacing: 16) {
                PermissionFeature(
                    icon: "photo.fill",
                    text: "Browse and organize your photos"
                )
                PermissionFeature(
                    icon: "trash.fill",
                    text: "Delete unwanted photos"
                )
                PermissionFeature(
                    icon: "lock.shield.fill",
                    text: "Your photos stay on your device"
                )
            }
            .padding(.top, 40)
            .padding(.horizontal, 40)
            .opacity(isAnimating ? 1.0 : 0.0)
            
            Spacer()
            
            // Buttons
            VStack(spacing: 16) {
                if photoAccessStatus == .denied || photoAccessStatus == .restricted {
                    Button(action: openSettings) {
                        Text("Open Settings")
                            .font(.system(size: min(17, UIScreen.main.bounds.width * 0.045), weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: max(54, UIScreen.main.bounds.width * 0.13))
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
                    
                    Button(action: checkPermissionStatus) {
                        Text("I've Enabled Access")
                            .font(.system(size: min(15, UIScreen.main.bounds.width * 0.04), weight: .medium))
                            .foregroundColor(Color(red: 0.5, green: 0.2, blue: 0.8))
                    }
                    .padding(.horizontal, 40)
                } else {
                    Button(action: requestPhotoAccess) {
                        HStack {
                            if isRequestingPermission {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Text("Continue")
                                    .font(.system(size: min(17, UIScreen.main.bounds.width * 0.045), weight: .semibold))
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
                    }
                    .disabled(isRequestingPermission)
                    .padding(.horizontal, 40)
                }
            }
            .padding(.bottom, 50)
            .opacity(isAnimating ? 1.0 : 0.0)
        }
        .onAppear {
            photoAccessStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Check permission status when app becomes active (user might have enabled it in Settings)
            checkPermissionStatus()
        }
    }
    
    private func requestPhotoAccess() {
        isRequestingPermission = true
        
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                isRequestingPermission = false
                photoAccessStatus = status
                
                switch status {
                case .authorized, .limited:
                    // Permission granted, continue to next step
                    onContinue()
                case .denied, .restricted:
                    // Permission denied - don't proceed, user must grant access
                    // The app will keep showing this screen until access is granted
                    break
                case .notDetermined:
                    // This shouldn't happen after requesting, but handle it
                    break
                @unknown default:
                    break
                }
            }
        }
    }
    
    private func openSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
    
    private func checkPermissionStatus() {
        photoAccessStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        if photoAccessStatus == .authorized || photoAccessStatus == .limited {
            onContinue()
        }
    }
}

// MARK: - Notification Permission View
struct NotificationPermissionView: View {
    let onContinue: () -> Void
    @State private var isRequestingPermission = false
    @StateObject private var notificationManager = NotificationManager.shared
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
                
                Image(systemName: "bell.badge.fill")
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
            Text("Stay on Track")
                .font(.system(size: min(32, UIScreen.main.bounds.width * 0.08), weight: .bold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .opacity(isAnimating ? 1.0 : 0.0)

            // Subtitle
            Text("Get daily reminders to keep your library organized")
                .font(.system(size: min(17, UIScreen.main.bounds.width * 0.045), weight: .regular))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 16)
                .opacity(isAnimating ? 1.0 : 0.0)
            
            // Reminder feature (matching PrivacyFeature style)
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.5, green: 0.2, blue: 0.8).opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Color(red: 0.5, green: 0.2, blue: 0.8))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("3x More Likely to Clean")
                        .font(.system(size: min(16, UIScreen.main.bounds.width * 0.04), weight: .semibold))
                        .foregroundColor(.primary)

                    Text("Users with reminders are 3x more likely to clean their library")
                        .font(.system(size: min(14, UIScreen.main.bounds.width * 0.035), weight: .regular))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            .padding(.top, 40)
            .padding(.horizontal, 40)
            .opacity(isAnimating ? 1.0 : 0.0)
            
            Spacer()
            
            // Buttons
            VStack(spacing: 16) {
                Button(action: requestNotificationPermission) {
                    HStack {
                        if isRequestingPermission {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Text("Enable Reminders")
                                .font(.system(size: min(17, UIScreen.main.bounds.width * 0.045), weight: .semibold))
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
                }
                .disabled(isRequestingPermission)
                .padding(.horizontal, 40)
                
                Button(action: {
                    // Skip and continue
                    onContinue()
                }) {
                    Text("Maybe Later")
                        .font(.system(size: min(15, UIScreen.main.bounds.width * 0.04), weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 40)
            }
            .padding(.bottom, 50)
            .opacity(isAnimating ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAnimating = true
            }
        }
    }
    
    private func requestNotificationPermission() {
        isRequestingPermission = true
        
        Task {
            let granted = await notificationManager.requestNotificationPermission()
            
            await MainActor.run {
                isRequestingPermission = false
                if granted {
                    notificationManager.scheduleDailyReminder()
                }
                // Proceed regardless of permission result
                onContinue()
            }
        }
    }
}

// MARK: - Permission Feature Row
struct PermissionFeature: View {
    let icon: String
    let text: LocalizedStringKey
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: min(20, UIScreen.main.bounds.width * 0.05)))
                .foregroundColor(Color(red: 0.5, green: 0.2, blue: 0.8))
                .frame(width: min(24, UIScreen.main.bounds.width * 0.06))
            
            Text(text)
                .font(.system(size: min(16, UIScreen.main.bounds.width * 0.04), weight: .regular))
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

#Preview {
    WelcomeFlowView {
    }
}
