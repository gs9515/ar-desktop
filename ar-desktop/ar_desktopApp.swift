//
//  ar_desktopApp.swift
//  ar-desktop
//
//  Created by Gary Smith on 2/17/25.
//

import SwiftUI
import Spatial

@main
struct ar_desktopApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        ImmersiveSpace(id: "StackingSpace") {
            StackingView().environmentObject(appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed) // Enables passthrough mode
        
        // 👉 Secondary window for file preview
        WindowGroup(id: "FilePreview") {
            PreviewWindowHostView()
                .environmentObject(appModel)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
    }
}

struct PreviewWindowHostView: View {
    @EnvironmentObject var appModel: AppModel

    var body: some View {
        Group {
            if let file = appModel.previewedFile {
                FilePreviewView(
                    label: file.label,
                    fileType: file.fileType,
                    fileLocation: file.fileLocation
                )
                .opacity(appModel.isPreviewVisible ? 1 : 0.0001) // 👈 essentially invisible
                .id(file.label + file.fileLocation)
            } else {
                Color.clear // Window must render something to stay alive
            }
        }
    }
}
