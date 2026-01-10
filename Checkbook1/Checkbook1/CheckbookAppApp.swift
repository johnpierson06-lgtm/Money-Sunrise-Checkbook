//
//  CheckbookAppApp.swift
//  CheckbookApp
//
//  Created by John Pierson on 10/31/25.
//

import SwiftUI
import UIKit

@main
struct CheckbookAppApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                LoginView()
            }
        }
    }
}
