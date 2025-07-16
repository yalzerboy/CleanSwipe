# RevenueCat Setup Guide for CleanSwipe

## 🚀 Setup Steps

### 1. Add RevenueCat Package to Xcode

1. Open your CleanSwipe project in Xcode
2. Go to **File → Add Package Dependencies**
3. Enter the RevenueCat URL: `https://github.com/RevenueCat/purchases-ios`
4. Choose the latest version and click **Add Package**
5. Select your app target and click **Add Package**

### 2. Configure RevenueCat Dashboard

1. Go to [RevenueCat Dashboard](https://app.revenuecat.com/)
2. Create a new project called "CleanSwipe"
3. Add your iOS app:
   - **App Store Connect App ID**: Get this from App Store Connect
   - **Bundle ID**: `com.yourcompany.cleanswipe` (or your actual bundle ID)

### 3. Create Subscription Product

1. In App Store Connect, create a new subscription:
   - **Product ID**: `cleanswipe_weekly_trial`
   - **Subscription Duration**: 1 week
   - **Free Trial**: 3 days
   - **Price**: £0.99/week (or your preferred price)

2. In RevenueCat Dashboard:
   - Go to **Products** → **Add Product**
   - Enter the product ID: `cleanswipe_weekly_trial`
   - Set as **Subscription**

### 4. Configure Entitlements

1. In RevenueCat Dashboard, go to **Entitlements**
2. Create a new entitlement called "premium"
3. Attach the `cleanswipe_weekly_trial` product to this entitlement

### 5. Get Your API Key

1. In RevenueCat Dashboard, go to **Project Settings**
2. Copy your **Public API Key**
3. Update `PurchaseManager.swift`:

```swift
private let revenueCatAPIKey = "YOUR_ACTUAL_API_KEY_HERE"
```

### 6. Update PurchaseManager.swift

Uncomment the RevenueCat code and remove the simulation code:

```swift
import RevenueCat  // Uncomment this line

// In the configure() method, uncomment:
Purchases.logLevel = .debug
Purchases.configure(withAPIKey: revenueCatAPIKey)
Purchases.shared.delegate = self

// Uncomment all the TODO sections and remove simulation methods
```

### 7. Add App Store Configuration

Add to your app's `Info.plist`:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

### 8. Test the Integration

1. Build and run on a device (not simulator)
2. Test the purchase flow in sandbox mode
3. Verify trial period starts correctly
4. Test subscription expiry handling

## 🔧 Code Changes Needed

### Remove from PurchaseManager.swift:
- All methods starting with `simulate...`
- The `DispatchQueue.main.asyncAfter` in `configure()`
- All `// TODO:` comments

### Uncomment in PurchaseManager.swift:
- `import RevenueCat`
- All RevenueCat API calls
- The `PurchasesDelegate` extension

## 📱 Current Implementation Status

✅ **Completed:**
- Purchase flow UI in onboarding
- Subscription status monitoring
- Trial period handling
- Error handling and user feedback
- Subscription status view for expired trials

🔄 **Ready for RevenueCat:**
- All RevenueCat integration points are prepared
- Just need to add the package and configure API key
- Remove simulation code and uncomment real implementation

## 🧪 Testing Checklist

- [ ] Purchase flow initiates correctly
- [ ] Trial period starts and is tracked
- [ ] Subscription status updates properly
- [ ] Expired trial shows upgrade screen
- [ ] Restore purchases works correctly
- [ ] Error handling displays appropriate messages
- [ ] App works with both trial and active subscriptions

## 📋 App Store Connect Requirements

1. **Subscription Terms**: Add clear terms about the 3-day trial and weekly billing
2. **Privacy Policy**: Update to mention subscription data collection
3. **App Review**: Ensure subscription purchase can be tested by reviewers
4. **Subscription Groups**: Create a subscription group for your weekly subscription

## 🎯 Next Steps

1. Add RevenueCat package to Xcode
2. Configure RevenueCat dashboard and App Store Connect
3. Update the API key in PurchaseManager.swift
4. Remove simulation code and uncomment RevenueCat integration
5. Test thoroughly on device
6. Submit for App Store review

Your subscription implementation is complete and ready for RevenueCat integration! 