//
//  ar_desktopApp.swift
//  ar-desktop
//
//  Created by Gary Smith on 2/17/25.
//

import SwiftUI

@main
struct ar_desktopApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
//                .environment(appModel)
        }
//        ImmersiveSpace(id: "AuraSpace") {
//            AuraView()
//        }

        ImmersiveSpace(id: "StackingSpace") {
            StackingView()
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed) // Enables passthrough mode
    }
}
