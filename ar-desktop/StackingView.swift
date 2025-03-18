//
//  StackingView.swift
//  ar-desktop
//
//  Created by Gary Smith on 2/23/25.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct StackingView: View {
    @StateObject var model = HandTrackingViewModel()
    
    
    var body: some View {
        RealityView { content in
            // add our content entity (holds cube and fingertips)
            content.add(model.setupContentEntity())
            
        }.task {
            // run ARKit Session (track environment)
            await model.runSession()
        }.task {
            // process our hand updates
            await model.processHandUpdates()
        }.task {
            // process our world reconstruction
            await model.processReconstructionUpdates()
        }.gesture(SpatialTapGesture().targetedToAnyEntity().onEnded({ value in
            
            Task {
                // place our cubes
                await model.placeObject(materialName: "Aura", label: "Files", color: .red)
            }
        }))
    }
}

//#Preview {
//    StackingView()
//}
