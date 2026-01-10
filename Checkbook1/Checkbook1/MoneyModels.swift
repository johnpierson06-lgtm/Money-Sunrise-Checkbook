import Foundation

struct MoneyTransaction: Identifiable {
    let id: UUID
    let accountId: UUID
    let amount: Double
    let date: Date
    let categoryPath: String?
    let payee: String?

    init(id: UUID = UUID(), accountId: UUID, amount: Double, date: Date, categoryPath: String? = nil, payee: String? = nil) {
        self.id = id
        self.accountId = accountId
        self.amount = amount
        self.date = date
        self.categoryPath = categoryPath
        self.payee = payee
    }
}

struct MoneyCategory: Identifiable {
    let id: UUID
    let name: String
    let parentId: UUID?

    init(id: UUID = UUID(), name: String, parentId: UUID? = nil) {
        self.id = id
        self.name = name
        self.parentId = parentId
    }
}

struct MoneyPayee: Identifiable {
    let id: UUID
    let name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}
