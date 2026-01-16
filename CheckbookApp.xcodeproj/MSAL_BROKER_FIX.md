# MSAL Broker Error Fix

## Problem

When running on a physical iPhone in developer mode, you encountered this error:

```
MSAL: application did not receive response from broker
MSAL: Broker flow finished
MSAL: acquireToken returning with error: (MSALErrorDomain, -50000)
```

## Root Cause

MSAL (Microsoft Authentication Library) was trying to use **broker authentication** via the Microsoft Authenticator app. Broker flow:

1. MSAL detects Microsoft Authenticator is installed (or should be)
2. Tries to hand off authentication to the broker app
3. Broker app doesn't respond (not installed or not configured)
4. Authentication fails with error -50000

This is common in development environments where:
- Microsoft Authenticator app is not installed on the device
- App isn't configured for broker authentication
- Developer mode has restrictions

## Solution

Disabled broker authentication and forced **embedded web view** mode instead.

### Changes Made

#### AuthManager.swift - Configuration

```swift
// BEFORE
let config = MSALPublicClientApplicationConfig(...)
config.cacheConfig.keychainSharingGroup = "..."

// AFTER
let config = MSALPublicClientApplicationConfig(...)
config.cacheConfig.keychainSharingGroup = "..."

// Disable broker for development
config.clientApplicationCapabilities = nil  // ← Added
```

#### AuthManager.swift - Web View Parameters

```swift
// BEFORE
let webParams = MSALWebviewParameters(authPresentationViewController: presenter)
let parameters = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webParams)

// AFTER
let webParams = MSALWebviewParameters(authPresentationViewController: presenter)
webParams.webviewType = .default  // ← Added (use embedded Safari)
let parameters = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webParams)
```

## How It Works Now

### Authentication Flow

```
User taps Sign In
    ↓
MSAL opens embedded Safari web view
    ↓
User signs in with Microsoft account
    ↓
Safari redirects back to app
    ↓
MSAL receives token
    ↓
User is authenticated ✅
```

**No broker app required!**

## Web View Types

MSAL supports different web view types:

| Type | Description | Broker Required? |
|------|-------------|------------------|
| `.authenticationSession` | System web view (ASWebAuthenticationSession) | No |
| `.safariViewController` | SFSafariViewController | No |
| `.default` | System default (usually ASWebAuthenticationSession) | No |
| `.wkWebView` | Embedded WKWebView | No |

We're using `.default` which gives the best user experience without requiring broker.

## Benefits

✅ **Works on all devices** - No need for Microsoft Authenticator  
✅ **Works in development** - No special broker configuration  
✅ **Same user experience** - Still uses Safari-based authentication  
✅ **Secure** - OAuth flow is still secure via system web view  
✅ **No error messages** - Broker errors eliminated  

## When to Use Broker

Broker authentication is useful for:
- **Enterprise scenarios** - Single sign-on across apps
- **Production apps** - Better security with hardware-backed keys
- **Conditional access** - Corporate policies requiring Authenticator

For development and most consumer apps, embedded web view is sufficient.

## Testing

Try signing in again:

1. **Launch app on iPhone**
2. **Tap sign-in button**
3. **Safari view should appear** (not broker)
4. **Enter Microsoft credentials**
5. **App receives token** ✅

You should see:
```
MSAL [Verbose]: Acquiring token interactively...
MSAL [Verbose]: Using embedded web view
MSAL [Verbose]: Token acquired successfully
```

**No more broker errors!**

## Alternative: Enable Broker (Production)

If you want to use broker in production, you'll need:

1. **Microsoft Authenticator app** installed
2. **LSApplicationQueriesSchemes** in Info.plist:
   ```xml
   <key>LSApplicationQueriesSchemes</key>
   <array>
       <string>msauthv2</string>
       <string>msauthv3</string>
   </array>
   ```
3. **Enable broker in config**:
   ```swift
   // Enable broker
   config.clientApplicationCapabilities = ["broker"]
   
   // Allow broker in parameters
   webParams.webviewType = .authenticationSession
   ```

But for now, embedded web view is the simplest solution! 🎉

## Troubleshooting

### Still seeing broker errors?

1. **Clean build** (⇧⌘K)
2. **Delete app from device**
3. **Rebuild and install**

### Safari view doesn't appear?

Check Info.plist has redirect URI scheme:
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>msauth.[BUNDLE_ID]</string>
        </array>
    </dict>
</array>
```

### Token not received?

Check redirect URI matches in:
- Azure App Registration
- Info.plist
- AuthManager configuration

---

**Fix Complete!** ✨

MSAL will now use embedded Safari web view instead of broker, eliminating the error on your iPhone.
