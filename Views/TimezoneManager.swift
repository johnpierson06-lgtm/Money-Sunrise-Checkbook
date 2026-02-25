//
//  TimezoneManager.swift
//  CheckbookApp
//
//  Manages the timezone offset for the Money file
//

import Foundation

enum TimezoneManagerError: Error, LocalizedError {
    case timezoneNotSet
    
    var errorDescription: String? {
        switch self {
        case .timezoneNotSet:
            return "Timezone offset has not been configured for this Money file"
        }
    }
}

/// Manages the timezone offset setting for the Money file
final class TimezoneManager {
    static let shared = TimezoneManager()
    
    private init() {}
    
    private let timezoneOffsetKey = "MoneyFile_TimezoneOffset"
    private let timezoneNameKey = "MoneyFile_TimezoneName"
    
    // MARK: - Standard US Timezones
    
    struct StandardTimezone: Identifiable {
        let id = UUID()
        let name: String
        let abbreviation: String
        let offsetHours: Int  // UTC offset (negative for west of Greenwich)
        
        var displayName: String {
            let sign = offsetHours <= 0 ? "" : "+"
            return "\(name) (\(abbreviation)) UTC\(sign)\(offsetHours)"
        }
    }
    
    static let standardTimezones: [StandardTimezone] = [
        StandardTimezone(name: "Eastern Time", abbreviation: "EST", offsetHours: -5),
        StandardTimezone(name: "Central Time", abbreviation: "CST", offsetHours: -6),
        StandardTimezone(name: "Mountain Time", abbreviation: "MST", offsetHours: -7),
        StandardTimezone(name: "Pacific Time", abbreviation: "PST", offsetHours: -8),
        StandardTimezone(name: "Alaska Time", abbreviation: "AKST", offsetHours: -9),
        StandardTimezone(name: "Hawaii Time", abbreviation: "HST", offsetHours: -10),
    ]
    
    // MARK: - Storage
    
    /// Save the timezone offset for the Money file
    func saveTimezoneOffset(_ offsetHours: Int, name: String) {
        UserDefaults.standard.set(offsetHours, forKey: timezoneOffsetKey)
        UserDefaults.standard.set(name, forKey: timezoneNameKey)
        UserDefaults.standard.synchronize()
        
        #if DEBUG
        print("[TimezoneManager] 🌍 Saved timezone offset: \(offsetHours) hours (\(name))")
        #endif
    }
    
    /// Get the saved timezone offset (returns nil if not set)
    func getTimezoneOffset() -> Int? {
        guard UserDefaults.standard.object(forKey: timezoneOffsetKey) != nil else {
            return nil
        }
        return UserDefaults.standard.integer(forKey: timezoneOffsetKey)
    }
    
    /// Get the saved timezone name
    func getTimezoneName() -> String? {
        return UserDefaults.standard.string(forKey: timezoneNameKey)
    }
    
    /// Check if timezone has been configured
    func isTimezoneConfigured() -> Bool {
        return getTimezoneOffset() != nil
    }
    
    /// Get timezone offset or throw error if not configured
    func requireTimezoneOffset() throws -> Int {
        guard let offset = getTimezoneOffset() else {
            throw TimezoneManagerError.timezoneNotSet
        }
        return offset
    }
    
    /// Clear the saved timezone (used when changing files)
    func clearTimezone() {
        UserDefaults.standard.removeObject(forKey: timezoneOffsetKey)
        UserDefaults.standard.removeObject(forKey: timezoneNameKey)
        UserDefaults.standard.synchronize()
        
        #if DEBUG
        print("[TimezoneManager] 🗑️ Cleared timezone settings")
        #endif
    }
    
    // MARK: - OLE Date Calculations
    
    /// Calculate the NULL date placeholder based on timezone offset
    /// Base: Feb 28, 10000 00:00:00, adjusted by timezone offset
    func calculateNullDate() throws -> Double {
        let offset = try requireTimezoneOffset()
        return calculateNullDate(offsetHours: offset)
    }
    
    /// Calculate NULL date with specific offset (for testing)
    func calculateNullDate(offsetHours: Int) -> Double {
        // Feb 28, 10000 at 00:00:00
        var components = DateComponents()
        components.year = 10000
        components.month = 2
        components.day = 28
        components.hour = 0
        components.minute = 0
        components.second = 0
        
        let calendar = Calendar(identifier: .gregorian)
        guard let baseDate = calendar.date(from: components) else {
            // This should never fail for a valid date
            fatalError("Failed to create base date for NULL calculation")
        }
        
        // OLE Automation date: days since Dec 30, 1899 00:00:00 UTC
        let oleEpochOffset: Double = 25569.0  // Days from OLE epoch to Unix epoch
        let unixTimestamp = baseDate.timeIntervalSince1970
        var days = (unixTimestamp / 86400.0) + oleEpochOffset
        
        // Subtract the offset hours
        // For UTC-7 (MST), offsetHours = -7, so we subtract -7/24 = add 7/24
        // Wait, this is backwards. Let me think...
        //
        // If Money file is in MST (UTC-7):
        // - We want Feb 27, 10000 17:00 (7 hours before Feb 28 00:00)
        // - We should subtract 7 hours from the base
        // - offsetHours = -7, but we want to subtract 7, so we need abs value
        //
        // Actually, the current code subtracts 7 hours for MST.
        // So if offsetHours = -7 (MST), we want to subtract 7 hours.
        // That means: days -= 7.0 / 24.0
        // So we use the absolute value
        days -= (Double(abs(offsetHours)) / 24.0)
        
        return days
    }
}
