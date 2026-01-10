import Foundation

/// Uses command-line mdb-export to read data from MDB files
/// This is a simpler alternative to linking the mdbtools library
struct MDBToolsCLI {
    
    enum MDBError: Error {
        case mdbToolsNotInstalled
        case exportFailed(String)
        case parseError(String)
    }
    
    /// Path to mdb-export tool (installed via Homebrew)
    static let mdbExportPath = "/opt/homebrew/bin/mdb-export"
    
    /// Check if mdb-export is available
    static func isAvailable() -> Bool {
        return FileManager.default.fileExists(atPath: mdbExportPath)
    }
    
    /// Export a table as CSV and parse it
    static func readTable(mdbPath: String, tableName: String) throws -> [[String: String]] {
        guard isAvailable() else {
            throw MDBError.mdbToolsNotInstalled
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: mdbExportPath)
        process.arguments = [mdbPath, tableName]
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw MDBError.exportFailed(errorString)
            }
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let csvString = String(data: outputData, encoding: .utf8) else {
                throw MDBError.parseError("Could not decode output as UTF-8")
            }
            
            return try parseCSV(csvString)
            
        } catch let error as MDBError {
            throw error
        } catch {
            throw MDBError.exportFailed(error.localizedDescription)
        }
    }
    
    /// Parse CSV string into array of dictionaries
    private static func parseCSV(_ csv: String) throws -> [[String: String]] {
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else {
            return []
        }
        
        // First line is headers
        let headers = lines[0].split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "\""))) }
        
        var rows: [[String: String]] = []
        
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }
            
            let values = parseCVSLine(String(line))
            guard values.count == headers.count else {
                continue // Skip malformed rows
            }
            
            var row: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                row[header] = values[index]
            }
            rows.append(row)
        }
        
        return rows
    }
    
    /// Parse a single CSV line, handling quoted fields
    private static func parseCVSLine(_ line: String) -> [String] {
        var values: [String] = []
        var currentValue = ""
        var insideQuotes = false
        
        for char in line {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                values.append(currentValue.trimmingCharacters(in: .whitespaces))
                currentValue = ""
            } else {
                currentValue.append(char)
            }
        }
        
        // Add the last value
        values.append(currentValue.trimmingCharacters(in: .whitespaces))
        
        return values
    }
    
    /// List all tables in an MDB file
    static func listTables(mdbPath: String) throws -> [String] {
        guard isAvailable() else {
            throw MDBError.mdbToolsNotInstalled
        }
        
        // Use mdb-tables command to list tables
        let process = Process()
        let mdbTablesPath = mdbExportPath.replacingOccurrences(of: "mdb-export", with: "mdb-tables")
        process.executableURL = URL(fileURLWithPath: mdbTablesPath)
        process.arguments = [mdbPath]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: outputData, encoding: .utf8) else {
            return []
        }
        
        // Tables are space-separated
        return output.split(separator: " ").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}
