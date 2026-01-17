# App Restart Navigation Fix

## Problem
The "Change File" and "Sign Out" buttons in AccountsView were clearing data but not properly resetting the app back to the splash screen. This caused navigation issues where the app wouldn't restart the authentication/file selection flow.

## Solution
Implemented a proper restart mechanism using the existing `AppCoordinator` that:
1. Clears all persistent data (file info, passwords, MSAL tokens as needed)
2. Resets the SplashScreenView state
3. Restarts the authentication flow from the beginning

## Changes Made

### 1. SplashScreenView.swift
- **Added `@EnvironmentObject var coordinator: AppCoordinator`**
  - Makes the view observe the coordinator's state
  
- **Added `.onChange(of: coordinator.shouldRestart)` modifier**
  - Watches for restart requests from the coordinator
  - Triggers the reset when needed
  
- **Added `resetToSplash()` function**
  - Resets all state variables to initial values (`isActive`, `navigationDestination`, `hasLRDFile`, `isReadOnly`)
  - Calls `coordinator.reset()` to clear coordinator flags
  - Restarts the authentication check after a brief delay

### 2. AppCoordinator.swift
- **Updated `requestChangeFile()`**
  - Now clears the password from keychain using `PasswordStore.shared.delete()`
  - Added error handling for password deletion
  
- **Updated `requestSignOut()`**
  - Now clears the password from keychain
  - Added error handling for password deletion

## How It Works

### Change File Flow:
1. User taps "Change File" in AccountsView
2. `coordinator.requestChangeFile()` is called
3. Coordinator clears:
   - Saved file ID (via `OneDriveFileManager.shared.clearSavedFile()`)
   - Password from keychain (via `PasswordStore.shared.delete()`)
4. Coordinator sets `shouldRestart = true`
5. SplashScreenView observes the change and calls `resetToSplash()`
6. App state resets and `checkAuthenticationStatus()` runs again
7. Since file is cleared but MSAL token exists, user goes to file selection
8. Flow continues: File Selection → Password Prompt → Accounts View

### Sign Out Flow:
1. User taps "Sign Out" in AccountsView
2. `coordinator.requestSignOut()` is called
3. Coordinator clears:
   - MSAL tokens (via `AuthManager.shared.signOut()`)
   - Saved file ID
   - Password from keychain
4. Coordinator sets `shouldRestart = true`
5. SplashScreenView observes the change and calls `resetToSplash()`
6. App state resets and `checkAuthenticationStatus()` runs again
7. Since both MSAL token and file are cleared, user goes to login
8. Flow continues: Login → File Selection → Password Prompt → Accounts View

## Key Benefits
- **Single Source of Truth**: The splash screen's `checkAuthenticationStatus()` logic determines navigation based on what's available
- **Clean State**: All persistent data is properly cleared
- **Consistent Flow**: Users get the same predictable experience whether starting fresh or after sign out/change file
- **Proper Navigation**: No navigation stack issues because we reset to the root (splash screen)

## Testing
To verify the fix works:
1. Sign in and select a file
2. View accounts
3. Tap "Change File" → Should return to splash, then show file selection
4. Select a file again
5. Tap "Sign Out" → Should return to splash, then show login prompt
6. Sign in again → Should show file selection
