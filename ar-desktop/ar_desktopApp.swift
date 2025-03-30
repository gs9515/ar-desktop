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
            StackingView().environmentObject(appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed) // Enables passthrough mode
        
        // 👉 Secondary window for file preview
        WindowGroup(id: "FilePreview") {
            if let file = appModel.previewedFile {
                VirtualFileView(
                    label: file.label,
                    fileType: file.fileType,
                    fileLocation: file.fileLocation
                )
                .environmentObject(appModel)
            }
        }
        .windowStyle(.plain) // ✅ default system window chrome with close/position bar
    }
}

