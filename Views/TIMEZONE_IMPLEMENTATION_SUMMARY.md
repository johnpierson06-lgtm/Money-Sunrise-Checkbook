# Timezone Implementation Summary

## Changes Made

### 1. **Created TimezoneManager.swift**
- Singleton manager for storing/retrieving timezone offset
- Includes list of standard US timezones (EST, CST, MST, PST, AKST, HST)
- Stores timezone offset (negative for west of UTC) in UserDefaults
- Provides `calculateNullDate()` method for computing the special NULL date (Feb 28, 10000) with offset
- Includes validation to prevent operations without configured timezone

### 2. **Created TimezoneSelectionView.swift**
- New view for first-time timezone selection
- Shows list of standard US timezones with their UTC offsets
- Saves selected timezone to TimezoneManager
- Clean, user-friendly interface with explanation of why timezone is needed

### 3. **Updated SplashScreenView.swift**
- Added `.timezoneSelection` to navigation destinations
- Modified flow: FileSelection → TimezoneSelection (if first time) → Accounts
- Checks if timezone is configured before navigating to accounts
- Only prompts for timezone on FIRST file open

### 4. **Updated AppCoordinator.swift**
- Added `TimezoneManager.shared.clearTimezone()` to both:
  - `requestChangeFile()` - Clears timezone when changing files
  - `requestSignOut()` - Clears timezone when signing out
- Ensures new file gets fresh timezone prompt

### 5. **Updated MDBToolsWriter.swift**
Major changes to date handling:

#### a) Modified `allocOleDate()` function:
- **OLD**: Hardcoded MST timezone and 7-hour offset
- **NEW**: 
  - Uses `TimezoneManager.shared.requireTimezoneOffset()` to get user's configured offset
  - Creates `TimeZone` dynamically from offset (e.g., UTC-7 for MST)
  - Parameter renamed: `subtractSevenHours` → `applyTimezoneOffset`
  - Applies offset dynamically: `days -= (Double(abs(timezoneOffsetHours)) / 24.0)`

#### b) NULL date calculation:
- **OLD**: Hardcoded `2958524.0` (Feb 28, 10000 minus 7 hours for MST)
- **NEW**: Calls `TimezoneManager.shared.calculateNullDate()` which:
  - Computes Feb 28, 10000 at 00:00:00
  - Subtracts user's timezone offset
  - Converts to OLE date format
  - Returns dynamic value based on user's configured timezone

#### c) Updated all `allocOleDate()` calls:
- Transaction dates (`dt`, `dtSerial`, etc.)
- Payee dates (`dtCCExp`, `dtLastModified`, `dtSerial`)
- All now use `applyTimezoneOffset: true` instead of `subtractSevenHours: true`

## User Flow

### First-Time File Open:
1. User signs in to OneDrive
2. User selects a .mny file
3. **NEW**: User is prompted to select timezone (only first time)
4. User enters password
5. Accounts load

### Subsequent Opens:
1. App loads with saved file
2. Timezone is already configured (skipped)
3. User enters password
4. Accounts load

### Changing Files:
1. User chooses "Change File"
2. File ID, password, AND timezone are cleared
3. User selects new file
4. Timezone prompt appears again (first time for this file)
5. User enters password
6. Accounts load

## Technical Details

### Timezone Offset Storage:
- Stored as INTEGER in UserDefaults
- Key: `MoneyFile_TimezoneOffset`
- Values: Negative for west of UTC (e.g., -7 for MST, -8 for PST)
- Timezone name also stored for display purposes

### OLE Date Calculation:
- OLE dates = days since December 30, 1899 00:00:00 UTC
- Formula: `(unixTimestamp / 86400.0) + 25569.0`
- Timezone offset applied: `days -= (offsetHours / 24.0)`
- Uses absolute value of offset since we always subtract

### NULL Date (Feb 28, 10000):
- Base date: February 28, 10000 at 00:00:00
- Offset applied to base date before OLE conversion
- Critical for Money file compatibility
- Used as placeholder for optional/future dates

## Error Handling:
- If timezone not configured when writing dates → `fatalError()` with clear message
- Prevents silent corruption of Money file with wrong timezone
- Forces proper configuration before any sync operations

## Testing Recommendations:
1. Test first-time file open flow
2. Test timezone selection UI
3. Test with different timezones (especially EST vs PST)
4. Verify NULL dates are calculated correctly
5. Test "Change File" clears timezone
6. Test sync with new timezone settings
7. Verify dates in Money Desktop after sync

## Notes:
- Only standard US timezones included (can be expanded if needed)
- Timezone tied to file, not user account
- Changing files prompts for new timezone
- No DST handling (uses standard time offsets only)
