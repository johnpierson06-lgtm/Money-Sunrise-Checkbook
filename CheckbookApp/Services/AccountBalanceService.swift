//
//  AccountBalanceService.swift
//  CheckbookApp
//
//  Service for calculating account balances including unsynced local transactions
//

import Foundation

/// Service for calculating account balances with local transactions
enum AccountBalanceService {
    
    /// Enhanced account summary that includes local transaction count
    struct EnhancedAccountSummary {
        let id: Int
        let name: String
        let beginningBalance: Decimal
        let currentBalance: Decimal
        let isFavorite: Bool
        let unsyncedTransactionCount: Int
        
        var hasUnsyncedTransactions: Bool {
            unsyncedTransactionCount > 0
        }
    }
    
    /// Read account summaries with balances that include local unsynced transactions
    static func readAccountSummariesWithLocal() throws -> [EnhancedAccountSummary] {
        // First get the base account summaries from the Money file
        let baseSummaries = try MoneyFileService.readAccountSummaries()
        
        // Get local unsynced transactions
        let localTransactions = try LocalDatabaseManager.shared.getUnsyncedTransactions()
        
        // Group local transactions by account
        var transactionsByAccount: [Int: [LocalTransaction]] = [:]
        for transaction in localTransactions {
            transactionsByAccount[transaction.hacct, default: []].append(transaction)
        }
        
        // Create enhanced summaries
        return baseSummaries.map { summary in
            let localTxns = transactionsByAccount[summary.id] ?? []
            
            // Calculate additional balance from local transactions
            let localBalance = localTxns.reduce(Decimal(0)) { $0 + $1.amt }
            
            return EnhancedAccountSummary(
                id: summary.id,
                name: summary.name,
                beginningBalance: summary.beginningBalance,
                currentBalance: summary.currentBalance + localBalance,
                isFavorite: summary.isFavorite,
                unsyncedTransactionCount: localTxns.count
            )
        }
    }
}
