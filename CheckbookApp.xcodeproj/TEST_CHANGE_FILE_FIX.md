# Quick Test Guide - Change File Fix

## Build First
```
⇧⌘K (Clean)
⌘B (Build)
⌘R (Run)
```

## Test: Change File Navigation

### Step 1: Get to Accounts
1. Launch app
2. Wait for splash screen
3. Enter password (if prompted)
4. You should see accounts list

### Step 2: Tap Change File
1. Look for **⋯** button (top left)
2. Tap it
3. Tap **"Change File"**

### Step 3: Verify Behavior
✅ **Should happen:**
- App shows splash screen briefly
- Navigates to OneDrive file picker
- You can browse folders
- You can select a different file

❌ **Should NOT happen:**
- App closes/terminates
- Returns to same accounts screen
- Shows previously selected file

### Step 4: Select Different File
1. Browse OneDrive
2. Select a different .mny file
3. Enter password
4. ✅ Should show accounts from NEW file

## Test: Sign Out

### Step 1: From Accounts
1. Tap **⋯** (top left)
2. Tap **"Sign Out"**

### Step 2: Verify
✅ **Should happen:**
- App shows splash screen briefly
- Navigates to login screen
- "Sign in with Microsoft" button visible

❌ **Should NOT happen:**
- App closes/terminates
- Shows accounts screen
- Shows file picker

### Step 3: Sign Back In
1. Tap "Sign in with Microsoft"
2. Complete auth flow
3. ✅ Should go to file picker
4. Select file
5. Enter password
6. ✅ See accounts

## Test: Normal Launch (No Changes)

### Step 1: Close App
1. Swipe up to close app completely
2. Or tap Stop in Xcode

### Step 2: Relaunch
1. Tap app icon or Run in Xcode
2. ✅ Splash screen shows
3. ✅ Auto-loads your file
4. ✅ Password prompt
5. ✅ Accounts display

## Console Verification

### When "Change File" works correctly:
```
[SplashScreenView] 🔄 Handling restart request...
[SplashScreenView] 🚀 Starting authentication check...
[SplashScreenView] ✅ User is authenticated
[SplashScreenView] 📂 No persisted file - showing file selection
```

### When "Sign Out" works correctly:
```
[SplashScreenView] 🔄 Handling restart request...
[SplashScreenView] 🚀 Starting authentication check...
[SplashScreenView] 🔐 User needs to authenticate - showing login
```

## Success Checklist

After testing all scenarios:

- [ ] "Change File" → File picker (not same accounts)
- [ ] Can select different file from picker
- [ ] "Sign Out" → Login screen
- [ ] Can sign back in
- [ ] Normal launch → Auto-loads file
- [ ] App never closes/terminates during navigation
- [ ] Smooth transitions (no jarring exits)
- [ ] Console shows expected messages

All checked? ✅ Fix is working! 🎉

## If Something's Wrong

### Issue: "Change File" still shows same accounts
**Check:**
1. Is `AppCoordinator.swift` in your project?
2. Did the build succeed?
3. Try: Clean Build Folder, rebuild

### Issue: App still closes when tapping menu items
**Check:**
1. Make sure `exit(0)` was removed from AccountsView
2. Verify coordinator calls are in place
3. Check console for errors

### Issue: Build errors
**Common:**
- "Cannot find 'AppCoordinator'" → Add file to target
- "Ambiguous use of 'coordinator'" → Check @StateObject declarations

## Files That Changed

✅ `AppCoordinator.swift` - NEW file (add to target!)
✅ `SplashScreenView.swift` - Added coordinator
✅ `AccountsView.swift` - Removed exit(0), added coordinator

## Quick Debug

If "Change File" doesn't work:

1. **Set a breakpoint** in `AppCoordinator.requestChangeFile()`
2. Tap "Change File"
3. Verify breakpoint hits
4. Step through to see file ID being cleared
5. Verify `shouldRestart` becomes true
6. Check if SplashScreenView's `.onChange` fires

That should help identify where it's failing!

