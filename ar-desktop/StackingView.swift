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
    var files: [File]
}

// Define your custom file type (optional, for a more Swifty approach)
struct File {
    var label: String
    var fileType: String
    var fileLocation: String
}

// Custom subclass to store extra metadata
struct CustomMetadata {
    let label: String
    let color: Color
    let materialName: String
    let files: [File]
}

// Custom component to attach metadata to ModelEntity
struct CustomMetadataComponent: Component {
    var metadata: CustomMetadata
}

extension ModelEntity {
    var customMetadata: CustomMetadata? {
        get {
            if let component = self.components[CustomMetadataComponent.self] {
                return component.metadata
            }
            return nil
        }
        set {
            if let newMetadata = newValue {
                self.components.set(CustomMetadataComponent(metadata: newMetadata))
            } else {
                self.components.remove(CustomMetadataComponent.self)
            }
        }
    }
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
    @State private var didRunSetup = false
    @State private var shouldPlaceObject = false

    
    // Data structure and index for the next object(s) to palce
    @State var currentIndex = 0
    @State var objectsToPlace: [ObjectData] = [
        ObjectData(materialName: "Red_v2", label: "Communication", color: hexStringToUIColor(hex: "#FF4D0D"), files: [
            File(label: "Messages", fileType: "application", fileLocation: "messages.png"),
            File(label: "WhatsApp", fileType: "application", fileLocation: "whatsapp.png"),
            File(label: "Mail", fileType: "application", fileLocation: "mail.png"),
            File(label: "Letter from Mom", fileType: "pdf", fileLocation: "notes.png"),
            File(label: "Letter from Bobby", fileType: "pdf", fileLocation: "notes.png")
        ]),
        ObjectData(materialName: "Yellow_v2", label: "Office", color: hexStringToUIColor(hex:"#F4FE04"), files: [
            File(label: "Word", fileType: "application", fileLocation: "/src/word"),
        ]),
        ObjectData(materialName: "Green_v2", label: "Browsers", color: hexStringToUIColor(hex:"#2ABB5D"), files: [
            File(label: "Chrome", fileType: "application", fileLocation: "/src/chrome"),
        ]),
        ObjectData(materialName: "Blue_v2", label: "Memories", color: hexStringToUIColor(hex:"#5074FD"), files: [
            File(label: "Dad", fileType: "photo", fileLocation: "/src/dad.jpg"),
        ]),
        ObjectData(materialName: "Purple_v2", label: "Documents", color: hexStringToUIColor(hex:"#AE69FB"), files: [
            File(label: "Independent Work Proposal", fileType: "file", fileLocation: "/src/iw_prop.pdf"),
        ]),
    ]
    
    var body: some View {
        RealityView { content in
            // add our content entity (holds cube and fingertips)
            content.add(model.setupContentEntity())
            
      }.onAppear {
            if !didRunSetup {
                Task {
                    await model.collectDesktopCenterOnPinch() // Your one-time function
                    didRunSetup = true
                }
            }
        }
        .task {
            // run ARKit Session (track environment)
            await model.runSession()
        }.task {
            // process our hand updates
            await model.processHandUpdates()
        }.task {
            // process our world reconstruction
            await model.processReconstructionUpdates()
        }.task {
            // placing globs
            for await _ in model.didPinchStream {
                if model.objectsPlaced < 5 && currentIndex < objectsToPlace.count {
                    let data = objectsToPlace[currentIndex]
                    if let entity = await model.placeObject(
                        meshName: "Domed_Cylinder",
                        materialName: data.materialName,
                        label: data.label,
                        color: data.color
                    ) {
                        entity.customMetadata = CustomMetadata(
                            label: data.label,
                            color: data.color,
                            materialName: data.materialName,
                            files: data.files
                        )
                    }
                    currentIndex += 1
                }
            }
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    Task {
//                        // PLACE GLOBS
//                        if model.objectsPlaced < 5 && currentIndex < objectsToPlace.count {
//                            let data = objectsToPlace[currentIndex]
//                            if let entity = await model.placeObject(
//                                meshName: "Domed_Cylinder",
//                                materialName: data.materialName,
//                                label: data.label,
//                                color: data.color
//                            ) {
//                                entity.customMetadata = CustomMetadata(
//                                    label: data.label,
//                                    color: data.color,
//                                    materialName: data.materialName,
//                                    files: data.files
//                                )
//                            }
//                            currentIndex += 1
//                        // Make opening a group possible on these blobs
                        if let entity = value.entity as? ModelEntity, let metadata = entity.customMetadata {
                            await model.openGroup(label: metadata.label,
                                                  color: metadata.color,
                                                  materialName: metadata.materialName,
                                                  files: metadata.files.map { [
                                                      "label": $0.label,
                                                      "fileType": $0.fileType,
                                                      "fileLocation": $0.fileLocation
                                                  ] })
                        }
                    }
                }
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
