import Foundation
import UIKit
import MSAL

#if canImport(UIKit)
private func topMostViewController(base: UIViewController? = UIApplication.shared.connectedScenes
    .compactMap { $0 as? UIWindowScene }
    .flatMap { $0.windows }
    .first(where: { $0.isKeyWindow })?.rootViewController) -> UIViewController? {
    if let nav = base as? UINavigationController { return topMostViewController(base: nav.visibleViewController) }
    if let tab = base as? UITabBarController { return topMostViewController(base: tab.selectedViewController) }
    if let presented = base?.presentedViewController { return topMostViewController(base: presented) }
    return base
}

private func resolvePresenter(preferred: UIViewController?) -> UIViewController? {
    // Prefer the provided presenter if its view is attached to a window
    if let vc = preferred, vc.viewIfLoaded?.window != nil { return vc }
    // Fallback to the top-most visible controller
    if let top = topMostViewController(), top.viewIfLoaded?.window != nil { return top }
    // Fallback to key window's root controller
    if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
       let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController,
       root.viewIfLoaded?.window != nil {
        return root
    }
    return nil
}
#endif

final class AuthManager {
    static let shared = AuthManager()

    private let clientId: String
    private let redirectUri: String
    private let authority: String
    private let graphEndpoint: String

    private var msalApp: MSALPublicClientApplication

    private init() {
        let bundle = Bundle.main
        self.clientId = bundle.object(forInfoDictionaryKey: "MSALClientId") as? String ?? "mycheckbookapp"
        self.redirectUri = bundle.object(forInfoDictionaryKey: "MSALRedirectUri") as? String ?? "msauth.com.your.bundle.id://auth"
        self.authority = bundle.object(forInfoDictionaryKey: "MSALAuthority") as? String ?? "https://login.microsoftonline.com/consumers"
        self.graphEndpoint = bundle.object(forInfoDictionaryKey: "MSALGraphEndpoint") as? String ?? "https://graph.microsoft.com/"

        let authorityURL = try? MSALAuthority(url: URL(string: self.authority)!)
        let config = MSALPublicClientApplicationConfig(clientId: self.clientId, redirectUri: self.redirectUri, authority: authorityURL)
        config.cacheConfig.keychainSharingGroup = "com.microsoft.identity.universalstorage" // Ensure this is also added under Keychain Sharing entitlements
        do {
            msalApp = try MSALPublicClientApplication(configuration: config)
        } catch {
            fatalError("Unable to create MSALPublicClientApplication: \(error)")
        }
        // Enable MSAL logging for diagnostics
        MSALGlobalConfig.loggerConfig.logLevel = .verbose
        MSALGlobalConfig.loggerConfig.setLogCallback { (level, message, containsPII) in
            print("MSAL [\(level)]: \(message)")
        }
    }

    @discardableResult
    public func signIn(scopes: [String], presentingViewController: UIViewController?) async throws -> String {
        #if canImport(UIKit)
        guard let presenter = resolvePresenter(preferred: presentingViewController) else {
            throw NSError(domain: "AuthManager", code: -10, userInfo: [NSLocalizedDescriptionKey: "No presenter available for MSAL web view"])
        }
        let webParams = MSALWebviewParameters(authPresentationViewController: presenter)
        let parameters = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webParams)
        #else
        let parameters = MSALInteractiveTokenParameters(scopes: scopes)
        #endif
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            #if canImport(UIKit)
            DispatchQueue.main.async {
                self.msalApp.acquireToken(with: parameters) { (result, error) in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let accessToken = result?.accessToken else {
                        let err = NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No access token received"])
                        continuation.resume(throwing: err)
                        return
                    }
                    continuation.resume(returning: accessToken)
                }
            }
            #else
            self.msalApp.acquireToken(with: parameters) { (result, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let accessToken = result?.accessToken else {
                    let err = NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No access token received"])
                    continuation.resume(throwing: err)
                    return
                }
                continuation.resume(returning: accessToken)
            }
            #endif
        }
    }

    @discardableResult
    public func signIn(scopes: [String]) async throws -> String {
        return try await signIn(scopes: scopes, presentingViewController: nil)
    }

    public func signIn(scopes: [String], completion: @escaping (String?, Error?) -> Void) {
        Task {
            do {
                let token = try await signIn(scopes: scopes)
                completion(token, nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    public func signIn(scopes: [String], presentingViewController: UIViewController?, completion: @escaping (String?, Error?) -> Void) {
        Task {
            do {
                let token = try await signIn(scopes: scopes, presentingViewController: presentingViewController)
                completion(token, nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    private func getCurrentAccount(completion: @escaping (MSALAccount?, Error?) -> Void) {
        do {
            let cachedAccounts = try msalApp.allAccounts()
            if let account = cachedAccounts.first {
                completion(account, nil)
            } else {
                let err = NSError(domain: "AuthManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "No account found"])
                completion(nil, err)
            }
        } catch {
            completion(nil, error)
        }
    }

    public func acquireTokenSilent(scopes: [String]) async throws -> String {
        let account: MSALAccount = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MSALAccount, Error>) in
            self.getCurrentAccount { acct, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let acct = acct {
                    continuation.resume(returning: acct)
                } else {
                    let err = NSError(domain: "AuthManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "No account found"])
                    continuation.resume(throwing: err)
                }
            }
        }
        let silentParameters = MSALSilentTokenParameters(scopes: scopes, account: account)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            self.msalApp.acquireTokenSilent(with: silentParameters) { (result, error) in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let accessToken = result?.accessToken else {
                    let err = NSError(domain: "AuthManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No access token received"])
                    continuation.resume(throwing: err)
                    return
                }
                continuation.resume(returning: accessToken)
            }
        }
    }

    public func acquireTokenSilent(scopes: [String], completion: @escaping (String?, Error?) -> Void) {
        Task {
            do {
                let token = try await acquireTokenSilent(scopes: scopes)
                completion(token, nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    public func signOut(completion: @escaping (Error?) -> Void) {
        do {
            let accounts = try msalApp.allAccounts()
            var lastError: Error?
            for account in accounts {
                do {
                    try msalApp.remove(account)
                } catch {
                    lastError = error
                }
            }
            DispatchQueue.main.async {
                completion(lastError)
            }
        } catch {
            DispatchQueue.main.async {
                completion(error)
            }
        }
    }

    public func downloadFile(accessToken: String, fileId: String, suggestedFileName: String, parentFolderId: String?, completion: @escaping (URL?, Error?) -> Void) {
        let base = self.graphEndpoint.hasSuffix("/") ? self.graphEndpoint : self.graphEndpoint + "/"
        guard let url = URL(string: "\(base)v1.0/me/drive/items/\(fileId)/content") else {
            DispatchQueue.main.async {
                let err = NSError(domain: "AuthManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Invalid download URL"])
                completion(nil, err)
            }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let task = URLSession.shared.downloadTask(with: request, completionHandler: { tempUrl, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(nil, error) }
                return
            }
            guard let tempUrl = tempUrl else {
                let err = NSError(domain: "AuthManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "No file downloaded"])
                DispatchQueue.main.async { completion(nil, err) }
                return
            }

            do {
                let fileManager = FileManager.default
                let documentsUrl = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let destinationUrl = documentsUrl.appendingPathComponent(suggestedFileName)

                if fileManager.fileExists(atPath: destinationUrl.path) {
                    try fileManager.removeItem(at: destinationUrl)
                }
                // Move the file from the temporary location before it is cleaned up by the system
                try fileManager.moveItem(at: tempUrl, to: destinationUrl)
                DispatchQueue.main.async { completion(destinationUrl, nil) }
            } catch {
                DispatchQueue.main.async { completion(nil, error) }
            }
        })
        task.resume()
    }
}

