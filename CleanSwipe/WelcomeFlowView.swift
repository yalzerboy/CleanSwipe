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
            // Baby blue background
            Color(red: 0.7, green: 0.85, blue: 1.0)
                .ignoresSafeArea()
            
            if isCheckingPermissions {
                // Loading indicator while checking permissions
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text("Checking permissions...")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
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
            let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
            let notificationStatus = notificationSettings.authorizationStatus
            
            await MainActor.run {
                if notificationStatus == .authorized {
                    // Notification permission already granted, complete flow
                    onComplete()
                } else {
                    // Show notification permission screen
                    currentStep = .notifications
                }
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
    
    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 20) {
                Text("Welcome to CleanSwipe")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("Get ready to clean up your camera roll")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 20) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                
                if photoAccessStatus == .denied || photoAccessStatus == .restricted {
                    Text("Photo access is required to use CleanSwipe. Please enable it in Settings.")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                } else {
                    Text("But first things first, please allow CleanSwipe access to your photo gallery")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            
            Spacer()
            
            VStack(spacing: 16) {
                if photoAccessStatus == .denied || photoAccessStatus == .restricted {
                    Button(action: openSettings) {
                        Text("Open Settings")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 40)
                    
                    Button(action: checkPermissionStatus) {
                        Text("I've Enabled Access")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.white.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
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
                                Text("Allow Access to Photos")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isRequestingPermission)
                    .padding(.horizontal, 40)
                }
            }
            .padding(.bottom, 50)
        }
        .padding(.top, 80)
        .onAppear {
            photoAccessStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
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
    
    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 20) {
                Text("Clean-up Reminders")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("We want to let you know periodically to clean up your gallery and if there's any photos from this day that can be reviewed")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            VStack(spacing: 20) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                
                Text("Please allow notifications so we can do this")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
            
            Button(action: requestNotificationPermission) {
                HStack {
                    if isRequestingPermission {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Text("Allow Notifications")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isRequestingPermission)
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .padding(.top, 80)
    }
    
    private func requestNotificationPermission() {
        isRequestingPermission = true
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                isRequestingPermission = false
                // Proceed regardless of permission result
                onContinue()
            }
        }
    }
}

#Preview {
    WelcomeFlowView {
        print("Welcome flow completed")
    }
} 