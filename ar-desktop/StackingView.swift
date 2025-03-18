//
//  StackingView.swift
//  ar-desktop
//
//  Created by Gary Smith on 2/23/25.
//

import SwiftUI
import RealityKit
import RealityKitContent
import Spatial

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
        }
        .gesture(
            model.objectsPlaced < 5 ? // Limit placing to 5 objects
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded({ value in
                    Task {
                        await model.placeObject(materialName: "Aura", label: "Files", color: .red)
                    }
                }) : nil
        )
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    if let entity = value.entity as? ModelEntity {
                        entity.position = value.convert(value.location3D, from: .local, to: entity.parent!)
                    }
                }
        )
    }
}

//#Preview {
//    StackingView()
//}
