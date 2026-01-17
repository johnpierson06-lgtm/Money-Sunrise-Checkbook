# Simple File Picker - Direct Navigation ✅

## What You Wanted

When clicking `⋯` → "Change File", you just want to:
1. Show the OneDrive file browser
2. Select a new file
3. Re-enter password
4. See accounts from new file

**No need** to go back to splash screen or complex navigation!

## The Simple Solution

Added a **sheet** that presents the file browser directly from AccountsView.

## How It Works

```
Tap "Change File"
   ↓
showingFilePicker = true
   ↓
Sheet appears with file browser
   ↓
Browse OneDrive folders
   ↓
Tap a .mny file
   ↓
File is downloaded
   ↓
Sheet dismisses
   ↓
Password prompt appears
   ↓
Enter password
   ↓
See accounts from new file ✅
```

## Code Changes

### AccountsView.swift

#### Added State Variable:
```swift
@State private var showingFilePicker = false
```

#### Updated changeFile():
```swift
private func changeFile() {
    print("[AccountsView] 🔄 Change file requested")
    showingFilePicker = true  // Just show the picker!
}
```

#### Added Sheet:
```swift
.sheet(isPresented: $showingFilePicker) {
    FilePickerWrapper(onFileSelected: handleFileSelected)
}
```

#### Added File Handler:
```swift
private func handleFileSelected(fileId: String, fileName: String, parentFolderId: String?) {
    // Save file
    OneDriveFileManager.shared.saveSelectedFile(...)
    
    // Download file
    OneDriveFileManager.shared.refreshLocalMnyFile { ... }
    
    // Show password prompt
    showPasswordPrompt = true
}
```

#### Added Helper Views:
- **FilePickerWrapper** - Gets auth token and shows browser
- **FileBrowserView** - Navigable folder browser

## Features

### FilePickerWrapper
- Gets OneDrive access token
- Shows loading state
- Handles errors
- Has Cancel button

### FileBrowserView
- Lists folders and files
- Folders are NavigationLinks (drill down)
- .mny files are selectable buttons
- Shows checkmark icon on files
- Other files are disabled

## Build & Test

1. **Clean:** `Shift+Cmd+K`
2. **Build:** `Cmd+B`
3. **Run:** `Cmd+R`

### Test Flow:

1. **Get to Accounts screen**
   - Launch app
   - Enter password if needed
   - See your accounts

2. **Tap `⋯` → "Change File"**
   - ✅ Sheet slides up
   - ✅ Shows "Loading OneDrive..."
   - ✅ Then shows file browser

3. **Browse folders**
   - ✅ Tap folders to drill down
   - ✅ See .mny files with checkmark icons
   - ✅ Back button works

4. **Select a file**
   - ✅ Tap a .mny file
   - ✅ Sheet dismisses
   - ✅ Loading indicator shows
   - ✅ Password prompt appears

5. **Enter password**
   - ✅ Enter password
   - ✅ See accounts from new file

6. **Cancel**
   - ✅ Tap Cancel button
   - ✅ Returns to accounts
   - ✅ Old file still loaded

## Console Output

```
[AccountsView] 🔄 Change file requested
[AccountsView] 📁 File selected: NewFile.mny
```

## Benefits

| Old Approach | New Approach |
|--------------|--------------|
| ❌ Go to splash screen | ✅ Stay in AccountsView |
| ❌ Complex coordinator | ✅ Simple sheet |
| ❌ Full app reset | ✅ Just pick file |
| ❌ Multiple screens | ✅ Direct navigation |

## UI/UX

### Sheet Presentation
- Slides up from bottom
- Covers current screen
- Cancel button top-left
- "Select Money File" title

### File Browser
- Familiar file picker UI
- Folders with folder icons
- Files with document icons
- .mny files have blue checkmarks
- Drill down into folders
- Back navigation works

### After Selection
- Sheet auto-dismisses
- Brief loading state
- Password prompt
- New accounts loaded

## No More Coordinator Needed

The `AppCoordinator` approach was for full app navigation. For just changing files, a simple sheet is perfect!

You can still keep `signOut()` using the coordinator for logging out, but `changeFile()` is now much simpler.

## Error Handling

### No Token
Shows error message with "Retry" button

### OneDrive Error
Shows error message with "Retry" button

### Download Error
Shows error in AccountsView (existing error handling)

### Wrong Password
Shows password error (existing error handling)

## Summary

✅ **Direct file picker** from AccountsView
✅ **Sheet presentation** (professional)
✅ **Simple implementation** (no coordinator needed)
✅ **Familiar UI** (standard file browser)
✅ **Easy to use** (tap folder, select file, done)
✅ **No app restart** or complex navigation

Just tap "Change File", pick a file, and you're done! 🎉

