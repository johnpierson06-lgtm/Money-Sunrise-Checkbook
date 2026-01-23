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
    public let name: String  // Maps to: szFull
    public let parentId: Int? // Maps to: hcatParent
    public let level: Int    // Maps to: nLevel

    public init(id: Int, name: String, parentId: Int? = nil, level: Int = 0) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.level = level
    }
}

// MARK: - Payee Model

public struct MoneyPayee: Identifiable, Hashable, Codable, Sendable {
    public let id: Int       // Maps to: hpay
    public let name: String  // Maps to: szFull

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}
// MARK: - Transaction Display Model

/// Rich transaction model with resolved category and payee names for display
public struct TransactionDetail: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let date: Date
    public let amount: Decimal
    public let payeeName: String?
    public let categoryName: String?
    public let memo: String?
    
    public init(id: Int, date: Date, amount: Decimal, payeeName: String?, categoryName: String?, memo: String?) {
        self.id = id
        self.date = date
        self.amount = amount
        self.payeeName = payeeName
        self.categoryName = categoryName
        self.memo = memo
    }
    
    /// Create from a transaction with lookups
    public init(transaction: MoneyTransaction, payees: [Int: MoneyPayee], categories: [Int: MoneyCategory]) {
        self.id = transaction.id
        self.date = transaction.date
        self.amount = transaction.amount
        self.payeeName = transaction.payeeId.flatMap { payees[$0]?.name }
        
        // Build full category path (e.g., "Bills : Electricity")
        self.categoryName = transaction.categoryId.flatMap { catId in
            Self.buildCategoryPath(categoryId: catId, categories: categories)
        }
        
        self.memo = transaction.memo
    }
    
    /// Build full category path by following parent relationships
    private static func buildCategoryPath(categoryId: Int, categories: [Int: MoneyCategory]) -> String? {
        guard let category = categories[categoryId] else {
            #if DEBUG
            print("[TransactionDetail] Category \(categoryId) not found in lookup")
            #endif
            return nil
        }
        
        var path: [String] = []
        var currentCategory = category
        var visited: Set<Int> = []
        
        // Add current category
        path.append(currentCategory.name)
        visited.insert(currentCategory.id)
        
        #if DEBUG
        print("[TransactionDetail] Building path for category \(categoryId): '\(currentCategory.name)' (level=\(currentCategory.level), parent=\(currentCategory.parentId?.description ?? "nil"))")
        #endif
        
        // Walk up the parent chain
        while let parentId = currentCategory.parentId,
              !visited.contains(parentId), // Prevent infinite loops
              let parent = categories[parentId] {
            
            visited.insert(parentId)
            
            #if DEBUG
            print("[TransactionDetail]   -> Parent \(parentId): '\(parent.name)' (level=\(parent.level))")
            #endif
            
            // Skip root categories (INCOME, EXPENSE)
            if parent.name == "INCOME" || parent.name == "EXPENSE" {
                break
            }
            
            path.insert(parent.name, at: 0)
            currentCategory = parent
        }
        
        let result = path.joined(separator: " : ")
        
        #if DEBUG
        print("[TransactionDetail]   Final path: '\(result)'")
        #endif
        
        return result
    }
}

