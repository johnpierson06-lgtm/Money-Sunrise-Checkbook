//
//  CheckbookAppApp.swift
//  CheckbookApp
//
//  Created by John Pierson on 10/31/25.
//

import SwiftUI
import UIKit
import MSAL

// AppDelegate to handle MSAL broker callbacks
class CheckbookAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        print("[CheckbookApp] Received URL callback: \(url)")
        
        // Handle MSAL broker response
        let handled = MSALPublicClientApplication.handleMSALResponse(url, sourceApplication: options[UIApplication.OpenURLOptionsKey.sourceApplication] as? String)
        
        if handled {
            print("[CheckbookApp] ✅ URL handled by MSAL broker")
        } else {
            print("[CheckbookApp] ⚠️ URL NOT handled by MSAL")
        }
        
        return handled
    }
}

@main
struct CheckbookAppApp: App {
    @UIApplicationDelegateAdaptor(CheckbookAppDelegate.self) var appDelegate
    @StateObject private var coordinator = AppCoordinator.shared
    
    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .environmentObject(coordinator)
                .onOpenURL { url in
                    // Handle URL here for SwiftUI lifecycle
                    print("[CheckbookApp] SwiftUI onOpenURL: \(url)")
                    _ = MSALPublicClientApplication.handleMSALResponse(url, sourceApplication: nil)
                }
        }
    }
}

