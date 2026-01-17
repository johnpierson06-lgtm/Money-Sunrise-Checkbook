//
//  MoneyModels.swift
//  CheckbookApp
//
//  Data models for Microsoft Money file parsing
//

import Foundation

// MARK: - Account Model

public struct MoneyAccount: Identifiable, Hashable, Codable, Sendable {
    public let id: Int              // Maps to: hacct
    public let name: String          // Maps to: szFull
    public let beginningBalance: Decimal  // Maps to: amtOpen

    public init(id: Int, name: String, beginningBalance: Decimal) {
        self.id = id
        self.name = name
        self.beginningBalance = beginningBalance
    }
}

// MARK: - Transaction Model

public struct MoneyTransaction: Identifiable, Hashable, Codable, Sendable {
    public let id: Int          // Maps to: htrn
    public let accountId: Int   // Maps to: hacct
    public let date: Date       // Maps to: dt
    public let amount: Decimal  // Maps to: amt
    public let payeeId: Int?    // Maps to: lHpay
    public let categoryId: Int? // Maps to: hcat
    public let memo: String?    // Maps to: mMemo
    
    // Fields needed for proper balance calculation
    public let frequency: Int           // Maps to: frq (-1 = posted transaction, 3 = recurring schedule)
    public let transactionTypeFlags: Int // Maps to: grftt (bit 6 = split detail)
    public let instanceNumber: Int?     // Maps to: iinst (recurring instance number)

    public init(id: Int, accountId: Int, date: Date, amount: Decimal, 
                payeeId: Int? = nil, categoryId: Int? = nil, memo: String? = nil,
                frequency: Int = -1, transactionTypeFlags: Int = 0, instanceNumber: Int? = nil) {
        self.id = id
        self.accountId = accountId
        self.date = date
        self.amount = amount
        self.payeeId = payeeId
        self.categoryId = categoryId
        self.memo = memo
        self.frequency = frequency
        self.transactionTypeFlags = transactionTypeFlags
        self.instanceNumber = instanceNumber
    }
    
    /// Determines if this transaction should be counted in balance calculations
    /// - Returns: true if this is a posted transaction (not a split detail or future scheduled instance)
    public var shouldCountInBalance: Bool {
        // Only count posted transactions (frq == -1)
        guard frequency == -1 else { return false }
        
        // Exclude split transaction details (grftt >= 64) unless it's a posted recurring instance
        if transactionTypeFlags >= 64 {
            return instanceNumber != nil
        }
        
        return true
    }
}

// MARK: - Category Model

public struct MoneyCategory: Identifiable, Hashable, Codable, Sendable {
    public let id: Int       // Maps to: hcat
    public let name: String  // Maps to: szName

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - Payee Model

public struct MoneyPayee: Identifiable, Hashable, Codable, Sendable {
    public let id: Int       // Maps to: hpay
    public let name: String  // Maps to: szName

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}
