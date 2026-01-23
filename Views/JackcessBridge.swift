//
//  JackcessBridge.swift
//  CheckbookApp
//
//  Native iOS bridge that replicates Jackcess insertion behavior
//  Uses JackcessCompatibleMDBWriter for native binary manipulation
//

import Foundation

/// Native iOS implementation of Jackcess-compatible Money file insertion
enum JackcessBridge {
    
    enum InsertError: Error, LocalizedError {
        case fileNotFound
        case readFailed
        case writeFailed
        case invalidFormat
        case invalidPassword
        case encryptionFailed
        
        var errorDescription: String? {
            switch self {
            case .fileNotFound: return "Money file not found"
            case .readFailed: return "Failed to read Money file"
            case .writeFailed: return "Failed to write to Money file"
            case .invalidFormat: return "Invalid Money file format"
            case .invalidPassword: return "Invalid password"
            case .encryptionFailed: return "Failed to encrypt Money file"
            }
        }
    }
    
    /// Insert a transaction into a Money file (.mny)
    /// This mimics the Jackcess Table.addRow() method
    static func insertTransaction(_ transaction: LocalTransaction, into fileURL: URL, password: String) throws {
        #if DEBUG
        print("═══════════════════════════════════════")
        print("[JackcessBridge] INSERT TRANSACTION")
        print("═══════════════════════════════════════")
        print("htrn: \(transaction.htrn)")
        print("hacct: \(transaction.hacct)")
        print("amt: \(transaction.amt)")
        print("payee: \(transaction.lHpay ?? -1)")
        #endif
        
        // Step 1: Decrypt the .mny file to get the .mdb
        let decryptedPath = try MoneyDecryptorBridge.decryptToTempFile(fromFile: fileURL.path, password: password)
        
        #if DEBUG
        print("✓ Decrypted to: \(decryptedPath)")
        #endif
        
        // Step 2: Use JackcessCompatibleMDBWriter to insert transaction
        let writer = try JackcessCompatibleMDBWriter(filePath: decryptedPath)
        try writer.insertTransaction(transaction)
        try writer.save()
        
        #if DEBUG
        print("✓ Inserted transaction into MDB")
        #endif
        
        // Step 3: Re-encrypt to .mny format
        try MoneyDecryptorBridge.encryptFromTempFile(tempFilePath: decryptedPath, toFile: fileURL.path, password: password)
        
        #if DEBUG
        print("✓ Re-encrypted to .mny")
        print("═══════════════════════════════════════")
        #endif
    }
    
    /// Insert a payee into a Money file (.mny)
    static func insertPayee(_ payee: LocalPayee, into fileURL: URL, password: String) throws {
        #if DEBUG
        print("═══════════════════════════════════════")
        print("[JackcessBridge] INSERT PAYEE")
        print("═══════════════════════════════════════")
        print("hpay: \(payee.hpay)")
        print("name: \(payee.szFull)")
        #endif
        
        // Step 1: Decrypt
        let decryptedPath = try MoneyDecryptorBridge.decryptToTempFile(fromFile: fileURL.path, password: password)
        
        // Step 2: Use JackcessCompatibleMDBWriter to insert payee
        let writer = try JackcessCompatibleMDBWriter(filePath: decryptedPath)
        try writer.insertPayee(payee)
        try writer.save()
        
        #if DEBUG
        print("✓ Inserted payee into MDB")
        #endif
        
        // Step 3: Re-encrypt
        try MoneyDecryptorBridge.encryptFromTempFile(tempFilePath: decryptedPath, toFile: fileURL.path, password: password)
        
        #if DEBUG
        print("✓ Re-encrypted to .mny")
        print("═══════════════════════════════════════")
        #endif
    }
}
