//
//  NewTransactionView.swift
//  CheckbookApp
//
//  View for creating a new transaction with category and payee selection
//

import SwiftUI

struct NewTransactionView: View {
    let account: UIAccount
    
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var amount = ""
    @State private var selectedCategory: CategoryWithType?
    @State private var selectedPayee: MoneyPayee?
    
    @State private var categories: [MoneyCategory] = []
    @State private var payees: [MoneyPayee] = []
    @State private var localPayees: [MoneyPayee] = []  // Payees from local DB
    
    @State private var showingCategoryPicker = false
    @State private var showingPayeePicker = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isSaving = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Date Section
                Section("Date") {
                    DatePicker("Transaction Date", selection: $date, displayedComponents: [.date])
                        .datePickerStyle(.compact)
                }
                
                // Amount Section
                Section("Amount") {
                    HStack {
                        Text("$")
                            .foregroundColor(.secondary)
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .font(.title3)
                    }
                    
                    if let category = selectedCategory {
                        HStack {
                            Image(systemName: category.isExpense ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                .foregroundColor(category.isExpense ? .red : .green)
                            Text(category.isExpense ? "Expense (negative)" : "Income (positive)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Category Section
                Section("Category") {
                    Button {
                        if !isLoading {
                            showingCategoryPicker = true
                        }
                    } label: {
                        HStack {
                            if let category = selectedCategory {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(category.displayPath)
                                        .foregroundColor(.primary)
                                    Text(category.isExpense ? "Expense" : "Income")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("Select Category")
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(isLoading)
                }
                
                // Payee Section
                Section("Payee") {
                    Button {
                        if !isLoading {
                            showingPayeePicker = true
                        }
                    } label: {
                        HStack {
                            Text(selectedPayee?.name ?? "Select Payee")
                                .foregroundColor(selectedPayee == nil ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(isLoading)
                }
                
                // Error Section
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTransaction()
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .sheet(isPresented: $showingCategoryPicker) {
                CategoryPickerView(
                    categories: categories,
                    selectedCategory: $selectedCategory
                )
            }
            .sheet(isPresented: $showingPayeePicker) {
                PayeePickerView(
                    payees: allPayees,
                    selectedPayee: $selectedPayee,
                    onAddNew: { newPayeeName in
                        addNewPayee(name: newPayeeName)
                    }
                )
            }
            .overlay {
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Loading categories and payees...")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        .padding(24)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                    }
                } else if isSaving {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Saving transaction...")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        .padding(24)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                    }
                }
            }
            .onAppear {
                loadData()
            }
            .alert("Error Loading Data", isPresented: Binding<Bool>(
                get: { errorMessage != nil && !isLoading && !isSaving },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Retry") {
                    loadData()
                }
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }
    
    private var allPayees: [MoneyPayee] {
        // Combine file payees and local payees, removing duplicates
        var combined = payees
        for localPayee in localPayees {
            if !combined.contains(where: { $0.id == localPayee.id }) {
                combined.append(localPayee)
            }
        }
        return combined.sorted { $0.name < $1.name }
    }
    
    private var isValid: Bool {
        guard !amount.isEmpty,
              let _ = Decimal(string: amount),
              selectedCategory != nil,
              selectedPayee != nil else {
            return false
        }
        return true
    }
    
    private func loadData() {
        isLoading = true
        errorMessage = nil
        
        #if DEBUG
        print("[NewTransactionView] Starting to load categories and payees...")
        #endif
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                #if DEBUG
                print("[NewTransactionView] Getting local file...")
                #endif
                
                let url = try MoneyFileService.ensureLocalFile()
                
                #if DEBUG
                print("[NewTransactionView] Local file URL: \(url)")
                print("[NewTransactionView] Loading password...")
                #endif
                
                let password = (try? PasswordStore.shared.load()) ?? ""
                
                #if DEBUG
                print("[NewTransactionView] Decrypting file...")
                #endif
                
                let decryptedPath = try MoneyDecryptorBridge.decryptToTempFile(fromFile: url.path, password: password)
                
                #if DEBUG
                print("[NewTransactionView] Decrypted path: \(decryptedPath)")
                print("[NewTransactionView] Parsing categories and payees...")
                #endif
                
                let parser = MoneyFileParser(filePath: decryptedPath)
                let cats = try parser.parseCategories()
                let pays = try parser.parsePayees()
                
                #if DEBUG
                print("[NewTransactionView] ✅ Successfully loaded \(cats.count) categories, \(pays.count) payees")
                #endif
                
                DispatchQueue.main.async {
                    self.categories = cats
                    self.payees = pays
                    self.isLoading = false
                    
                    #if DEBUG
                    print("[NewTransactionView] UI updated, loading complete")
                    #endif
                }
            } catch {
                #if DEBUG
                print("[NewTransactionView] ❌ Error loading data: \(error)")
                print("[NewTransactionView] Error type: \(type(of: error))")
                print("[NewTransactionView] Error description: \(error.localizedDescription)")
                #endif
                
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    
                    #if DEBUG
                    print("[NewTransactionView] Error state updated in UI")
                    #endif
                }
            }
        }
    }
    
    private func saveTransaction() {
        print("🚀🚀🚀 SAVE BUTTON PRESSED! 🚀🚀🚀")
        
        guard let amountDecimal = Decimal(string: amount),
              let categoryWithType = selectedCategory else {
            print("❌ Save validation failed - amount: \(amount), category: \(selectedCategory?.category.name ?? "nil")")
            return
        }
        
        print("✅ Validation passed - Amount: \(amountDecimal), Category: \(categoryWithType.category.name), Payee: \(selectedPayee?.name ?? "nil")")
        
        isSaving = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                print("💾 Creating transaction...")
                
                // Use temporary ID - use negative value to ensure uniqueness
                // During sync, this will be replaced with real htrn from Money file
                // Use lower 30 bits of millisecond timestamp to fit in Int32
                let timestamp = Int(Date().timeIntervalSince1970 * 1000)
                let tempId = -(timestamp & 0x3FFFFFFF)  // Negative, fits in Int32
                
                print("📋 Generated temp ID: \(tempId)")
                
                // Determine if amount should be negative (expense) or positive (income)
                let finalAmount = categoryWithType.isExpense ? -abs(amountDecimal) : abs(amountDecimal)
                
                print("💰 Final amount (after sign): \(finalAmount)")
                
                // Create new transaction
                let transaction = LocalTransaction.createNew(
                    id: tempId,
                    accountId: account.id,
                    date: date,
                    amount: finalAmount,
                    categoryId: categoryWithType.category.id,
                    payeeId: selectedPayee?.id,
                    memo: nil,
                    isTransfer: false
                )
                
                print("📝 Transaction created with:")
                print("   temp ID: \(transaction.htrn)")
                print("   Account: \(transaction.hacct)")
                print("   Amount: \(transaction.amt)")
                print("   Category: \(transaction.hcat?.description ?? "nil")")
                print("   Payee: \(transaction.lHpay?.description ?? "nil")")
                print("   Date: \(transaction.dt)")
                print("   Memo: \(transaction.mMemo ?? "nil")")
                print("💾 About to insert into database...")
                
                // Save to local database
                try LocalDatabaseManager.shared.insertTransaction(transaction)
                
                print("✅✅✅ DATABASE INSERT COMPLETED! ✅✅✅")
                
                DispatchQueue.main.async {
                    self.isSaving = false
                    
                    #if DEBUG
                    print("[NewTransactionView] ✅ Transaction saved with temp ID, Amount=\(finalAmount)")
                    #endif
                    
                    print("👋 Dismissing view...")
                    
                    // Dismiss the view
                    dismiss()
                }
            } catch {
                print("❌❌❌ ERROR SAVING TRANSACTION: \(error)")
                print("❌ Error type: \(type(of: error))")
                print("❌ Error description: \(error.localizedDescription)")
                
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to save: \(error.localizedDescription)"
                    self.isSaving = false
                }
            }
        }
    }
    
    private func addNewPayee(name: String) {
        #if DEBUG
        print("[NewTransactionView] addNewPayee called with name: '\(name)'")
        #endif
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let nextId = try LocalDatabaseManager.shared.getNextPayeeId()
                
                #if DEBUG
                print("[NewTransactionView] Next payee ID: \(nextId)")
                #endif
                
                let newPayee = LocalPayee.createNew(id: nextId, name: name)
                
                #if DEBUG
                print("[NewTransactionView] Created LocalPayee: hpay=\(newPayee.hpay), szFull='\(newPayee.szFull)'")
                #endif
                
                try LocalDatabaseManager.shared.insertPayee(newPayee)
                
                #if DEBUG
                print("[NewTransactionView] Inserted payee into database")
                #endif
                
                // Add to local payees list
                let moneyPayee = MoneyPayee(id: nextId, name: name)
                DispatchQueue.main.async {
                    self.localPayees.append(moneyPayee)
                    self.selectedPayee = moneyPayee
                    
                    #if DEBUG
                    print("[NewTransactionView] ✅ New payee added: ID=\(nextId), Name=\(name)")
                    #endif
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to add payee: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Category with Type Info

/// Wrapper for MoneyCategory that includes expense/income classification
struct CategoryWithType: Identifiable {
    let category: MoneyCategory
    let isExpense: Bool  // true if parent/grandparent is 131 (EXPENSE), false if 130 (INCOME)
    let displayPath: String  // Full path like "Automobile : Gasoline"
    
    var id: Int { category.id }
}

// MARK: - Category Picker View

struct CategoryPickerView: View {
    let categories: [MoneyCategory]
    @Binding var selectedCategory: CategoryWithType?
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var isSearchPresented = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredCategories) { categoryWithType in
                    Button {
                        selectedCategory = categoryWithType
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(categoryWithType.displayPath)
                                    .foregroundColor(.primary)
                                
                                HStack(spacing: 4) {
                                    Image(systemName: categoryWithType.isExpense ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(categoryWithType.isExpense ? .red : .green)
                                    Text(categoryWithType.isExpense ? "Expense" : "Income")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if selectedCategory?.id == categoryWithType.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search categories")
            .navigationTitle("Select Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Automatically show the search field when the view appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    isSearchPresented = true
                }
            }
        }
    }
    
    private var filteredCategories: [CategoryWithType] {
        let lookup = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        
        // Filter out root categories (INCOME, EXPENSE)
        let nonRootCategories = categories.filter { cat in
            cat.name != "INCOME" && cat.name != "EXPENSE"
        }
        
        // Map to CategoryWithType with full path
        let categoriesWithType = nonRootCategories.compactMap { cat -> CategoryWithType? in
            guard let typeInfo = determineType(for: cat, lookup: lookup) else {
                return nil
            }
            
            // Build display path
            let displayPath = buildCategoryPath(for: cat, lookup: lookup)
            
            return CategoryWithType(category: cat, isExpense: typeInfo, displayPath: displayPath)
        }
        
        // Filter by search text
        if searchText.isEmpty {
            return categoriesWithType.sorted { $0.displayPath < $1.displayPath }
        } else {
            return categoriesWithType
                .filter { $0.displayPath.localizedCaseInsensitiveContains(searchText) }
                .sorted { $0.displayPath < $1.displayPath }
        }
    }
    
    /// Build full category path like "Automobile : Gasoline"
    private func buildCategoryPath(for category: MoneyCategory, lookup: [Int: MoneyCategory]) -> String {
        var path: [String] = []
        var current = category
        var visited: Set<Int> = []
        
        // Add current category
        path.append(current.name)
        visited.insert(current.id)
        
        // Walk up the parent chain
        while let parentId = current.parentId {
            // Prevent infinite loops
            guard !visited.contains(parentId) else { break }
            visited.insert(parentId)
            
            guard let parent = lookup[parentId] else { break }
            
            // Skip root categories (INCOME, EXPENSE)
            if parent.name == "INCOME" || parent.name == "EXPENSE" {
                break
            }
            
            // Add parent to front of path
            path.insert(parent.name, at: 0)
            current = parent
        }
        
        return path.joined(separator: " : ")
    }
    
    /// Determine if category is expense (131) or income (130) by walking up parent chain
    private func determineType(for category: MoneyCategory, lookup: [Int: MoneyCategory]) -> Bool? {
        var current = category
        var visited: Set<Int> = []
        
        // Walk up the parent chain
        while let parentId = current.parentId {
            // Prevent infinite loops
            guard !visited.contains(parentId) else { break }
            visited.insert(parentId)
            
            // Check if this is the EXPENSE or INCOME root
            if parentId == 131 {
                return true  // Expense
            } else if parentId == 130 {
                return false  // Income
            }
            
            // Move to parent
            guard let parent = lookup[parentId] else { break }
            current = parent
        }
        
        // If we didn't find 130 or 131, check the category ID itself
        if category.id == 131 || category.parentId == 131 {
            return true  // Expense
        } else if category.id == 130 || category.parentId == 130 {
            return false  // Income
        }
        
        // Default to nil if we can't determine
        return nil
    }
}

// MARK: - Payee Picker View

struct PayeePickerView: View {
    let payees: [MoneyPayee]
    @Binding var selectedPayee: MoneyPayee?
    let onAddNew: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showingAddPayee = false
    @State private var newPayeeName = ""
    @State private var isSearchPresented = false
    
    var body: some View {
        NavigationStack {
            List {
                // Add new payee button (shown when searching)
                if !searchText.isEmpty && !filteredPayees.contains(where: { $0.name.localizedCaseInsensitiveCompare(searchText) == .orderedSame }) {
                    Button {
                        showingAddPayee = true
                        newPayeeName = searchText
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                            Text("Add \"\(searchText)\"")
                        }
                    }
                }
                
                // Existing payees
                ForEach(filteredPayees) { payee in
                    Button {
                        selectedPayee = payee
                        dismiss()
                    } label: {
                        HStack {
                            Text(payee.name)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            if selectedPayee?.id == payee.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, isPresented: $isSearchPresented, prompt: "Search payees")
            .navigationTitle("Select Payee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddPayee = true
                        newPayeeName = ""
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Add New Payee", isPresented: $showingAddPayee) {
                TextField("Payee Name", text: $newPayeeName)
                Button("Cancel", role: .cancel) {
                    newPayeeName = ""
                }
                Button("Add") {
                    if !newPayeeName.isEmpty {
                        onAddNew(newPayeeName)
                        selectedPayee = MoneyPayee(id: -1, name: newPayeeName)  // Temporary
                        dismiss()
                    }
                }
            } message: {
                Text("Enter the name of the new payee")
            }
            .onAppear {
                // Automatically show the search field when the view appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    isSearchPresented = true
                }
            }
        }
    }
    
    private var filteredPayees: [MoneyPayee] {
        if searchText.isEmpty {
            return payees.sorted { $0.name < $1.name }
        } else {
            return payees
                .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
                .sorted { $0.name < $1.name }
        }
    }
}

#Preview {
    NewTransactionView(account: UIAccount(id: 1, name: "Checking", openingBalance: 1000, currentBalance: 1500))
}
