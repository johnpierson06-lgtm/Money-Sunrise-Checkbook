import SwiftUI

struct NewTransactionView: View {
    let account: UIAccount
    @State private var amount: String = ""
    @State private var date = Date()
    @State private var selectedCategory: MoneyCategory?
    @State private var selectedPayee: MoneyPayee?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            TextField("Amount", text: $amount)
                .keyboardType(.decimalPad)
            
            DatePicker("Date", selection: $date, displayedComponents: .date)
            
            NavigationLink(destination: Text("Select Category Placeholder")) {
                HStack {
                    Text("Category")
                    Spacer()
                    Text(selectedCategory?.name ?? "Select")
                        .foregroundColor(.gray)
                }
            }
            
            NavigationLink(destination: Text("Select Payee Placeholder")) {
                HStack {
                    Text("Payee")
                    Spacer()
                    Text(selectedPayee?.name ?? "Select")
                        .foregroundColor(.gray)
                }
            }
            
            Button("Save") {
                dismiss()
            }
            .disabled(amount.isEmpty)
        }
        .navigationTitle("New Transaction")
    }
}

struct NewTransactionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            NewTransactionView(account: UIAccount(id: 1, name: "Checking", openingBalance: 1000, currentBalance: 1000))
        }
    }
}
