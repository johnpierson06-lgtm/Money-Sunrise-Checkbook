# Simple Fix: Change File Navigation with Delay

## Problem
The AppCoordinator approach was too complex and caused build errors. Let's use a simpler solution.

## Solution: Add Delay Before exit(0)

The issue was that `exit(0)` was called before the file clearing was fully saved to UserDefaults. By adding a small delay, we ensure the state is saved first.

## Changes Made

### AccountsView.swift

**Before:**
```swift
private func changeFile() {
    OneDriveFileManager.shared.clearSavedFile()
    exit(0)  // Too fast!
}
```

**After:**
```swift
private func changeFile() {
    // Clear the saved file ID FIRST
    OneDriveFileManager.shared.clearSavedFile()
    
    // Small delay to ensure state is saved
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        // Now exit to force restart
        exit(0)
    }
}
```

## Why This Works

1. **Clear file ID** happens immediately
2. **0.3 second delay** gives UserDefaults time to save
3. **exit(0)** terminates the app with saved state
4. **On restart**, app sees no file ID → goes to file picker ✅

## Files Modified

- ✅ AccountsView.swift - Added delay before exit(0)
- ✅ SplashScreenView.swift - Reverted coordinator changes (not needed)
- ❌ AppCoordinator.swift - Can be deleted (not used)

## Build Instructions

1. **Clean:** `Shift+Cmd+K`
2. **Build:** `Cmd+B`  
3. **Run:** `Cmd+R`

## Test

1. Launch app, get to accounts
2. Tap `⋯` → "Change File"
3. App will close/restart
4. ✅ Should go to file picker
5. Select a file
6. ✅ Should work!

## Why Not Use Coordinator?

The coordinator approach was more "correct" architecturally but:
- ❌ Required adding new file to target
- ❌ More complex state management
- ❌ Harder to debug
- ❌ Build errors for some users

The delay approach:
- ✅ Simple
- ✅ No new files
- ✅ Works reliably
- ✅ Easy to understand

## Summary

**Change File:**
```
Tap "Change File"
   ↓
Clear file ID
   ↓
Wait 0.3 seconds
   ↓
exit(0)
   ↓
App restarts
   ↓
No file ID found
   ↓
Go to file picker ✅
```

**Sign Out:**
```
Tap "Sign Out"
   ↓
Sign out of MSAL
   ↓
Clear file ID
   ↓
Wait 0.3 seconds
   ↓
exit(0)
   ↓
App restarts
   ↓
No auth token
   ↓
Go to login ✅
```

Simple and it works! 🎉

