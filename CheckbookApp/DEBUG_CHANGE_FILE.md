# Debug Guide - Change File Navigation

## Current Issue

When you tap "Change File", you see:
```
[AccountsView] 🔄 Change file requested
[AccountsView] 🔄 Change file requested
```

But no navigation happens.

## Expected Console Output

When "Change File" works correctly, you should see:

```
[AccountsView] 🔄 Change file requested
[AppCoordinator] 📂 requestChangeFile() called
[AppCoordinator] 🗑️ File ID cleared
[AppCoordinator] ✅ shouldRestart set to true
[SplashScreenView] 👀 onChange detected: shouldRestart = true
[SplashScreenView] 🔄 Handling restart request...
[AppCoordinator] 🔄 Resetting coordinator state
[SplashScreenView] 🚀 Performing authentication check...
[SplashScreenView] ✅ User is authenticated
[SplashScreenView] 📂 No persisted file - showing file selection
```

## Debugging Steps

### Step 1: Build with Enhanced Logging

1. **Clean:** `Shift+Cmd+K`
2. **Build:** `Cmd+B`
3. **Run:** `Cmd+R`

### Step 2: Test and Check Console

1. Get to Accounts screen
2. Open the **Debug Console** (Cmd+Shift+Y)
3. Tap `⋯` → "Change File"
4. **Watch the console carefully**

### Step 3: Diagnose Based on Output

#### Scenario A: Only see AccountsView logs
```
[AccountsView] 🔄 Change file requested
[AccountsView] 🔄 Change file requested
```

**Problem:** Coordinator is not being called
**Fix:** 
- Check that AccountsView has `@EnvironmentObject var coordinator: AppCoordinator`
- Check that CheckbookAppApp has `.environmentObject(coordinator)`

#### Scenario B: See AppCoordinator but no SplashScreenView onChange
```
[AccountsView] 🔄 Change file requested
[AppCoordinator] 📂 requestChangeFile() called
[AppCoordinator] 🗑️ File ID cleared
[AppCoordinator] ✅ shouldRestart set to true
```

**Problem:** SplashScreenView is not listening to coordinator changes
**Fix:**
- Check that SplashScreenView has `@EnvironmentObject var coordinator: AppCoordinator`
- Check that `.onChange(of: coordinator.shouldRestart)` is present
- Try force-unwrapping to check: Add `print("Coordinator in SplashScreen: \(coordinator)")` in body

#### Scenario C: See onChange but no navigation
```
[AppCoordinator] ✅ shouldRestart set to true
[SplashScreenView] 👀 onChange detected: shouldRestart = true
[SplashScreenView] 🔄 Handling restart request...
```

**Problem:** performAuthCheck() is not running or navigationDestination not being set
**Fix:**
- Add `print("navigationDestination = \(String(describing: navigationDestination))")` after setting it
- Add `print("isActive = \(isActive)")` after setting it

#### Scenario D: See everything but UI doesn't update
```
[SplashScreenView] 📂 No persisted file - showing file selection
```

**Problem:** SwiftUI view not re-rendering
**Fix:**
- Make sure all state changes happen on main thread (DispatchQueue.main.async)
- Try adding `@Published` to AppCoordinator properties (already done)
- Check for any .sheet or .fullScreenCover that might be blocking navigation

### Step 4: Manual Test

Add this to AccountsView temporarily to test coordinator directly:

```swift
.toolbar {
    ToolbarItem(placement: .navigationBarLeading) {
        Menu {
            Button("Test Coordinator") {
                print("[TEST] Setting coordinator.shouldRestart to true")
                coordinator.shouldRestart = true
            }
            
            Button(role: .destructive) {
                changeFile()
            } label: {
                Label("Change File", systemImage: "folder")
            }
            // ... rest of menu
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }
}
```

If "Test Coordinator" works but "Change File" doesn't, the issue is in `changeFile()` or `requestChangeFile()`.

### Step 5: Check Environment Object Chain

Add this to each view's body to verify coordinator is passed:

```swift
.onAppear {
    print("[\(String(describing: Self.self))] Coordinator: \(coordinator)")
}
```

Should print:
- `[CheckbookAppApp] Coordinator: <AppCoordinator>`
- `[SplashScreenView] Coordinator: <AppCoordinator>`
- `[AccountsView] Coordinator: <AppCoordinator>`

If any are missing or different instances, environment object isn't being passed correctly.

## Common Issues

### Issue: "Change file requested" appears twice
This is normal - SwiftUI might call the button action twice. It's fine as long as the rest of the flow works.

### Issue: Environment object error
```
Fatal error: No ObservableObject of type AppCoordinator found
```

**Fix:**
1. Make sure CheckbookAppApp has:
   ```swift
   @StateObject private var coordinator = AppCoordinator.shared
   .environmentObject(coordinator)
   ```

2. Make sure SplashScreenView and AccountsView have:
   ```swift
   @EnvironmentObject var coordinator: AppCoordinator
   ```

### Issue: onChange not firing
```swift
.onChange(of: coordinator.shouldRestart) { newValue in
    // Not called
}
```

**Fix:**
- Use `.onChange(of: coordinator.shouldRestart)` not `.onReceive()`
- Make sure `shouldRestart` is `@Published` in AppCoordinator (it is)
- Try adding `id(coordinator.shouldRestart)` to force view refresh

## Quick Fix Checklist

- [ ] Clean build folder
- [ ] Rebuild
- [ ] Check console shows all expected logs
- [ ] Verify environment objects are passed correctly
- [ ] Check navigationDestination is being set
- [ ] Check isActive is being set to true
- [ ] Verify view updates on main thread

## If Still Not Working

### Last Resort Test

Replace the `.onChange` with a manual binding test:

```swift
var body: some View {
    NavigationStack {
        Group {
            if coordinator.shouldRestart {
                Text("RESTART TRIGGERED!")
                    .onAppear {
                        handleRestart()
                    }
            } else if !isActive {
                // Splash screen
            } else {
                destinationView
            }
        }
    }
}
```

If this shows "RESTART TRIGGERED!" when you tap "Change File", then `.onChange` is the problem.
If it doesn't, then `coordinator.shouldRestart` is not being set to true.

## Build This Version and Report Back

After building with all the enhanced logging:

1. Tap "Change File"
2. Copy the **complete console output**
3. Share it so we can see exactly where it's failing

The logs will tell us exactly what's happening! 🔍

