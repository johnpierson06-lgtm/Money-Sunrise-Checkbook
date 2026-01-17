# Quick Build Checklist ✅

## Step 1: Clean
```
⇧⌘K (Shift+Cmd+K)
```

## Step 2: Build
```
⌘B (Cmd+B)
```

## Step 3: Expected Result
✅ **Build Succeeded**
❌ No errors
❌ No warnings about LoginView

## If Build Fails

### Error: "Multiple commands produce .md files"
**Fix:** Remove markdown files from "Copy Bundle Resources"

1. Select project (blue icon)
2. Select target
3. Build Phases tab
4. Expand "Copy Bundle Resources"
5. Remove all `.md` files
6. Clean and rebuild

### Error: "Invalid redeclaration of LoginView"
**Fix:** Check these renames were applied:

- [ ] LoginView.swift → `LegacyLoginView`
- [ ] MainFlowView.swift → `MainFlowLoginView`
- [ ] SplashScreenView.swift → `SplashLoginView` (should already be this)

### Error: "Missing argument for parameter"
**Fix:** Make sure PasswordPromptView has these parameters:
- `hasLRDWarning: Bool`
- `isReadOnly: Bool`

## Step 4: Run
```
⌘R (Cmd+R)
```

## Step 5: Verify

### You Should See:
1. ✅ Splash screen (2 seconds)
2. ✅ Green dollar icon
3. ✅ "Money Sunrise Checkbook"
4. ✅ Console: `[SplashScreenView] 🚀 Starting...`

### On Accounts Screen:
1. ✅ ⋯ menu (top left)
2. ✅ "Refresh" button (top right)
3. ✅ Account list

### Tap ⋯ Menu:
1. ✅ "Change File" option
2. ✅ "Sign Out" option

## Success! 🎉

If all checks pass, you're ready to go!

## Files Modified

✅ LoginView.swift
✅ MainFlowView.swift
✅ CheckbookAppApp.swift
✅ AccountsView.swift

## Files Not Modified (Already Correct)

✅ SplashScreenView.swift
✅ ViewControllerResolver.swift
✅ OneDriveFileManager.swift
✅ OneDriveAPI.swift
✅ AuthManager.swift

## Testing Scenarios

### Test First-Time User
Tap ⋯ → Sign Out

### Test Change File
Tap ⋯ → Change File

### Test Current File
Just relaunch app

All working! ✅

