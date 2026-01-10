# Xcode Setup Checklist for mdbtools

## ✅ Files You Need (Check if you have them)

### In your project, you should have these C source files:

**Core mdbtools files:**
- [x] `backend.c`
- [x] `catalog.c`
- [x] `data.c`
- [x] `file.c`
- [x] `index.c`
- [x] `money.c`
- [x] `props.c`
- [x] `sargs.c`
- [x] `table.c`

**Still need these (download from mdbtools):**
- [ ] `like.c` - Pattern matching
- [ ] `map.c` - Page mapping
- [ ] `write.c` - Write operations
- [ ] `worktable.c` - Temporary tables

**GLib implementation:**
- [x] `mdbfakeglib.c` - Just created for you!

**Headers:**
- [x] `mdbtools.h` - Main header
- [x] `mdbfakeglib.h` - GLib types
- [x] `mdbsql.h` - SQL support
- [x] `mdbprivate.h` - Just created for you!
- [ ] Need: `CheckbookApp-Bridging-Header.h` - To expose C to Swift

---

## 📋 Step-by-Step Setup Instructions

### Step 1: Add Missing Source Files

You still need these files from the mdbtools repository:

```bash
# In Terminal:
cd ~/Downloads/mdbtools/src/libmdb/

# Copy these files to your desktop:
cp like.c ~/Desktop/
cp map.c ~/Desktop/
cp write.c ~/Desktop/
cp worktable.c ~/Desktop/
```

Then in Xcode:
1. Right-click your project → "Add Files to CheckbookApp..."
2. Navigate to Desktop
3. Select: `like.c`, `map.c`, `write.c`, `worktable.c`
4. ✅ Check "Copy items if needed"
5. ✅ Make sure your app target is checked
6. Click "Add"

### Step 2: Verify All C Files Are in Your Project

In Xcode's Project Navigator (left sidebar), you should see:
- ✅ backend.c
- ✅ catalog.c
- ✅ data.c
- ✅ file.c
- ✅ index.c
- ✅ like.c (after adding)
- ✅ map.c (after adding)
- ✅ mdbfakeglib.c (just created!)
- ✅ money.c
- ✅ props.c
- ✅ sargs.c
- ✅ table.c
- ✅ write.c (after adding)
- ✅ worktable.c (after adding)

### Step 3: Verify All Headers Are in Your Project

You should see:
- ✅ mdbtools.h
- ✅ mdbfakeglib.h
- ✅ mdbsql.h
- ✅ mdbprivate.h (just created!)
- ✅ MoneyMDBHelpers.h (you already have this)

### Step 4: Create Bridging Header

1. In Xcode: File → New → File
2. Choose "Header File"
3. Name it: `CheckbookApp-Bridging-Header.h`
4. Save it in your project root (same folder as your .swift files)
5. Add this content:

```objc
#ifndef CheckbookApp_Bridging_Header_h
#define CheckbookApp_Bridging_Header_h

// Import mdbtools headers
#import "mdbtools.h"
#import "mdbfakeglib.h"
#import "mdbsql.h"
#import "MoneyMDBHelpers.h"

#endif
```

### Step 5: Configure Build Settings

1. Click on your **project** (top of navigator)
2. Select your **app target** (CheckbookApp)
3. Go to **Build Settings** tab
4. Search for "bridging"
5. Set **Objective-C Bridging Header** to: `CheckbookApp/CheckbookApp-Bridging-Header.h`
   - (Adjust path if your files are in a different folder)

### Step 6: Configure Header Search Paths

1. Still in Build Settings
2. Search for "header search"
3. Under **Header Search Paths**, add: `$(SRCROOT)/mdbtools_c`
   - This tells Xcode where to find your headers

### Step 7: Verify Compile Sources

1. Click on your **app target**
2. Go to **Build Phases** tab
3. Expand **Compile Sources**
4. Verify ALL your `.c` files are listed:
   - backend.c
   - catalog.c
   - data.c
   - file.c
   - index.c
   - like.c
   - map.c
   - mdbfakeglib.c ← Make sure this is included!
   - money.c
   - props.c
   - sargs.c
   - table.c
   - write.c
   - worktable.c
   - MoneyMDBHelpers.c

If any are missing:
- Click the "+" button
- Find the file and add it

---

## 🧪 Test the Setup

### Step 8: Try to Build

1. Press **Cmd+B** to build
2. Watch for errors in the Issue Navigator (left sidebar, ! icon)

### Common Errors and Fixes:

**Error: "Cannot find 'mdbprivate.h'"**
- Solution: Make sure mdbprivate.h is in the same folder as your other headers

**Error: "Undefined symbol _mdb_xxx"**
- Solution: A `.c` file is missing from Compile Sources (see Step 7)

**Error: "Undefined symbol _g_ptr_array_new"**
- Solution: Make sure `mdbfakeglib.c` is in Compile Sources

**Error: "Cannot find 'like.c'"** (or map.c, write.c, worktable.c)
- Solution: Download and add these files (see Step 1)

---

## 🎯 Quick Verification Checklist

Before building, verify:

- [ ] All 14 `.c` files are in your project
- [ ] All 5 `.h` files are in your project
- [ ] Bridging header created and configured in Build Settings
- [ ] All `.c` files appear in Build Phases → Compile Sources
- [ ] Header Search Paths includes your header location

---

## 📝 What to Do Next

Once the build succeeds:

1. **Test with your Money file:**
```swift
let parser = MoneyFileParser(filePath: "/path/to/your/decrypted.mny")
let accounts = try parser.parseAccounts()
print("Found \(accounts.count) accounts")
```

2. **Use MoneyFileService in your UI:**
```swift
@StateObject private var moneyService = MoneyFileService()

// In your view:
.task {
    await moneyService.loadFile(at: yourFilePath)
}
```

---

## 🆘 If You Still Get Errors

**Tell me:**
1. The exact error message
2. Which file/line it occurs in
3. Whether all the files from this checklist are in your project

**I can help you:**
- Debug specific compilation errors
- Create any missing files
- Fix configuration issues
