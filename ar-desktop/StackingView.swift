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

struct ObjectData {
    var materialName: String
    var label: String
    var color: Color
}

func hexStringToUIColor (hex:String) -> Color {
    var cString:String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

    if (cString.hasPrefix("#")) {
        cString.remove(at: cString.startIndex)
    }

    if ((cString.count) != 6) {
        return Color(UIColor.gray)
    }

    var rgbValue:UInt64 = 0
    Scanner(string: cString).scanHexInt64(&rgbValue)

    return Color(UIColor(
        red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
        green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
        blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
        alpha: CGFloat(1.0)
    ))
}

struct StackingView: View {
    @StateObject var model = HandTrackingViewModel()
    
    // Data structure and index for the next object(s) to palce
    @State var currentIndex = 0
    @State var objectsToPlace: [ObjectData] = [
        ObjectData(materialName: "Red", label: "Communication", color: hexStringToUIColor(hex:"#FF4D0D")),
        ObjectData(materialName: "Yellow", label: "Office", color: hexStringToUIColor(hex:"#F4FE04")),
        ObjectData(materialName: "Green", label: "Browsers", color: hexStringToUIColor(hex:"#2ABB5D")),
        ObjectData(materialName: "Blue", label: "Memories", color: hexStringToUIColor(hex:"#5074FD")),
        ObjectData(materialName: "Purple", label: "Documents", color: hexStringToUIColor(hex:"#AE69FB")),
    ]

    
    
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
            model.objectsPlaced < 5 && currentIndex < objectsToPlace.count ?
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded({ value in
                    Task {
                        let data = objectsToPlace[currentIndex]
                        await model.placeObject(
//                            meshName: "Domed_Cylinder",
                            materialName: data.materialName,
                            label: data.label,
                            color: data.color
                        )
                        currentIndex += 1
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
