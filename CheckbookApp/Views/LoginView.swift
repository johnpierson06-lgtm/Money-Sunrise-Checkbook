import SwiftUI

struct LoginView: View {
    @State private var isSignedIn = false
    @State private var errorMessage: String?
    @State private var presenterVC: UIViewController? = nil

    var body: some View {
        NavigationStack {
            if isSignedIn {
                NavigationLink(destination: FileSelectionView(), isActive: $isSignedIn) {
                    EmptyView()
                }
            } else {
                VStack(spacing: 20) {
                    Text("Sign In")
                        .font(.largeTitle)
                        .bold()

                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button("Sign in with Microsoft") {
                        Task {
                            do {
                                try await AuthManager.shared.signIn(scopes: ["Files.Read", "Files.ReadWrite"], presentingViewController: presenterVC)
                                isSignedIn = true
                                errorMessage = nil
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .navigationTitle("Sign In")
            }
        }
        .background(ViewControllerResolver { vc in self.presenterVC = vc })
        .onAppear {
            Task {
                do {
                    try await AuthManager.shared.acquireTokenSilent(scopes: ["Files.Read", "Files.ReadWrite"])
                    isSignedIn = true
                    errorMessage = nil
                } catch {
                    isSignedIn = false
                }
            }
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
    }
}
