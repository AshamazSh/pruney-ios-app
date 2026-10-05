//
//
// Created by Ashamaz Shidov on 04/10/2026
//
        

import SwiftUI

@main
struct PruneyApp: App {
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-resetOnboarding") {
            UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let scene = AppStoreScreenshot.scene {
                AppStoreScreenshotView(scene: scene)
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
