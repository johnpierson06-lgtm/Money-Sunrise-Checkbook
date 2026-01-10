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
    public let date: Date       // Maps to: dtrans
    public let amount: Decimal  // Maps to: amt
    public let payeeId: Int?    // Maps to: hpay
    public let categoryId: Int? // Maps to: hcat
    public let memo: String?    // Maps to: szMemo

    public init(id: Int, accountId: Int, date: Date, amount: Decimal, payeeId: Int? = nil, categoryId: Int? = nil, memo: String? = nil) {
        self.id = id
        self.accountId = accountId
        self.date = date
        self.amount = amount
        self.payeeId = payeeId
        self.categoryId = categoryId
        self.memo = memo
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
