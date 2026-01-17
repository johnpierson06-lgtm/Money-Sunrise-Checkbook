# Fix: Change File Navigation Issue ✅

## Problem

After selecting a file, tapping `⋯` → **"Change File"** would:
1. ❌ Close the app
2. ❌ Restart the app
3. ❌ Still show the same file (not navigate to file picker)

## Root Cause

The code was using `exit(0)` to restart the app:

```swift
private func changeFile() {
    OneDriveFileManager.shared.clearSavedFile()
    exit(0)  // ❌ Problem!
}
```

**Why it failed:**
1. `exit(0)` terminates the app immediately
2. iOS may save app state before the file ID is fully cleared
3. On restart, the app sees the old file ID still saved
4. Goes straight to accounts instead of file picker

## Solution

Created an **AppCoordinator** to handle navigation state properly:

### New File: AppCoordinator.swift

```swift
class AppCoordinator: ObservableObject {
    @Published var shouldRestart = false
    @Published var shouldClearFile = false
    @Published var shouldSignOut = false
    
    func requestChangeFile() {
        // Clear file ID FIRST
        OneDriveFileManager.shared.clearSavedFile()
        // Then signal restart
        shouldRestart = true
    }
}
```

### Updated: SplashScreenView.swift

- Added `@StateObject private var coordinator = AppCoordinator.shared`
- Added `.onChange(of: coordinator.shouldRestart)` listener
- Added `handleRestart()` method that:
  1. Resets coordinator state
  2. Resets splash screen state
  3. Re-runs authentication check
  4. Navigates to file picker (no saved file ID)

### Updated: AccountsView.swift

- Added `@StateObject private var coordinator = AppCoordinator.shared`
- Changed `changeFile()` to call `coordinator.requestChangeFile()`
- Changed `signOut()` to call `coordinator.requestSignOut()`
- **Removed `exit(0)` calls** - app stays running!

## How It Works Now

### Change File Flow:
```
User taps ⋯ → "Change File"
   ↓
coordinator.requestChangeFile()
   ↓
1. Clear file ID from UserDefaults
2. Set shouldRestart = true
   ↓
SplashScreenView detects change
   ↓
handleRestart() called:
  - Reset coordinator
  - Reset splash state
  - Re-run authentication check
   ↓
checkAuthenticationStatus():
  - User is authenticated ✅
  - No saved file ID ✅
   ↓
Navigate to file picker ✅
```

### Sign Out Flow:
```
User taps ⋯ → "Sign Out"
   ↓
coordinator.requestSignOut()
   ↓
1. Sign out of MSAL
2. Clear file ID
3. Set shouldRestart = true
   ↓
SplashScreenView detects change
   ↓
handleRestart() called
   ↓
checkAuthenticationStatus():
  - User is NOT authenticated ✅
   ↓
Navigate to login screen ✅
```

## Files Modified

### ✅ AppCoordinator.swift (NEW)
**Purpose:** Centralized state management for navigation
**Key Methods:**
- `requestChangeFile()` - Clears file, triggers restart
- `requestSignOut()` - Signs out, clears file, triggers restart
- `reset()` - Resets all flags

### ✅ SplashScreenView.swift
**Changes:**
- Added `@StateObject private var coordinator`
- Added `.onChange(of: coordinator.shouldRestart)`
- Added `handleRestart()` method

### ✅ AccountsView.swift
**Changes:**
- Added `@StateObject private var coordinator`
- Replaced `exit(0)` with coordinator calls
- Much simpler `changeFile()` and `signOut()` methods

## Testing

### Test 1: Change File
1. Launch app (should show your current file)
2. Enter password, see accounts
3. Tap `⋯` → **"Change File"**
4. ✅ App should reset to splash screen
5. ✅ Then navigate to OneDrive file picker
6. ✅ Select a different file
7. ✅ Enter password
8. ✅ See accounts from new file

### Test 2: Sign Out
1. From accounts screen
2. Tap `⋯` → **"Sign Out"**
3. ✅ App should reset to splash screen
4. ✅ Then navigate to login screen
5. ✅ Sign in with Microsoft
6. ✅ Navigate to file picker

### Test 3: Normal Launch (Existing File)
1. Close app completely
2. Relaunch
3. ✅ Splash screen
4. ✅ Auto-load file
5. ✅ Password prompt
6. ✅ Accounts

## Why This is Better

| Old Approach (exit(0)) | New Approach (AppCoordinator) |
|------------------------|-------------------------------|
| ❌ Terminates app | ✅ App stays running |
| ❌ Relies on iOS lifecycle | ✅ Controlled navigation |
| ❌ Timing issues | ✅ Predictable order |
| ❌ State may be saved too early | ✅ State cleared before restart |
| ❌ Not testable | ✅ Testable |
| ❌ Looks like a crash | ✅ Smooth transition |

## Console Output

### When "Change File" is tapped:

```
[SplashScreenView] 🔄 Handling restart request...
[SplashScreenView] 🚀 Starting authentication check...
[SplashScreenView] ⏰ Checking MSAL token...
[SplashScreenView] ✅ User is authenticated
[SplashScreenView] 📂 No persisted file - showing file selection
```

### When "Sign Out" is tapped:

```
[SplashScreenView] 🔄 Handling restart request...
[SplashScreenView] 🚀 Starting authentication check...
[SplashScreenView] ⏰ Checking MSAL token...
[SplashScreenView] 🔐 User needs to authenticate - showing login
```

## Build Instructions

1. **Clean:** `Shift+Cmd+K`
2. **Build:** `Cmd+B`
3. **Run:** `Cmd+R`

## Success Criteria

After building and running:

- [ ] "Change File" navigates to file picker (doesn't retain old file)
- [ ] "Sign Out" navigates to login screen
- [ ] App doesn't close/terminate
- [ ] Smooth transitions
- [ ] No state retention issues

All checked? ✅ Fixed! 🎉

## Additional Benefits

### Better Architecture
- Centralized navigation state
- Easier to add more navigation actions later
- Testable coordinator pattern

### Better UX
- App doesn't appear to crash
- Smooth transitions
- Predictable behavior

### Better Debugging
- Clear console logs
- Can see state changes
- Easier to trace issues

## Summary

**Before:**
- `exit(0)` → app terminates → iOS relaunches → timing issues → wrong state

**After:**
- Coordinator → clear state → signal restart → controlled reset → correct state ✅

The app now properly navigates back to the file picker when "Change File" is tapped!

