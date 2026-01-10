import Foundation

struct Account: Identifiable {
    let id = UUID()
    let name: String
    let balance: Double
}
