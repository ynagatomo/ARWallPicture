//
//  arwallpictureApp.swift
//  arwallpicture
//
//  Created by Yasuhito Nagatomo on 2022/12/13.
//

import SwiftUI

@main
struct ARWallpictureApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            HomeView(appState: appState)
        }
    }
}
