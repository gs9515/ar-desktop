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
    var preview: String
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
    @Environment(\.openWindow) var openWindow
    @EnvironmentObject var appModel: AppModel
    @Environment(\.dismissWindow) var dismissWindow

    
    // Data structure and index for the next object(s) to palce
    @State var currentIndex = 0
    @State var objectsToPlace: [ObjectData] = [
        ObjectData(materialName: "Red_v2", label: "Communication", color: hexStringToUIColor(hex: "#FF4D0D"), files: [
            File(label: "Messages", fileType: "application", preview:"messages.png", fileLocation: "messages.png"),
            File(label: "WhatsApp", fileType: "application", preview:"whatsapp.png", fileLocation: "whatsapp.png"),
            File(label: "Mail", fileType: "application", preview:"mail.png", fileLocation: "mail.png"),
            File(label: "Letter to Grandad", fileType: "pdf", preview:"notes.png", fileLocation: "Letter_to_Grandad.pdf"),
            File(label: "Emergency Phone Numbers", fileType: "pdf", preview:"notes.png", fileLocation: "OKC_Emergencies.pdf")
        ]),
        ObjectData(materialName: "Yellow_v2", label: "Office", color: hexStringToUIColor(hex:"#F4FE04"), files: [
            File(label: "Word", fileType: "application", preview:"", fileLocation: "/src/word"),
        ]),
        ObjectData(materialName: "Green_v2", label: "Browsers", color: hexStringToUIColor(hex:"#2ABB5D"), files: [
            File(label: "Chrome", fileType: "application", preview:"", fileLocation: "/src/chrome"),
        ]),
        ObjectData(materialName: "Blue_v2", label: "Memories", color: hexStringToUIColor(hex:"#5074FD"), files: [
            File(label: "Northern Lights", fileType: "photo", preview:"northern_lights.jpeg", fileLocation: "northern_lights.jpeg"),
            File(label: "Felix", fileType: "photo", preview:"felix1.JPG", fileLocation: "felix1.JPG"),
            File(label: "Foster Kitty", fileType: "photo", preview:"foster.jpeg", fileLocation: "foster.jpeg"),
        ]),
        ObjectData(materialName: "Purple_v2", label: "Documents", color: hexStringToUIColor(hex:"#AE69FB"), files: [
            File(label: "Independent Work Proposal", fileType: "file", preview:"", fileLocation: "/src/iw_prop.pdf"),
        ]),
    ]
    
    var body: some View {
        RealityView { content in
            // add our content entity (holds objects and fingertips)
            content.add(model.setupContentEntity())
            
      }.onAppear {
            if !didRunSetup {
                model.appModel = appModel // ✅ Inject it here
                model.openWindowAction = { id in openWindow(id: id) }
                model.dismissWindowAction = { id in dismissWindow(id: id) }
                Task {
                    // One-time function to collect the center of the desktop (where the user starts their pointer finger)
                    await _ = model.collectDesktopCenterOnPinch()
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
                        if let entity = value.entity as? ModelEntity {
                            // Check if this entity is a file (has file metadata)
                            if let fileMetadata = entity.components[FileMetadataComponent.self] {
                                // It's a file entity
                                await model.openFile(label: fileMetadata.label,
                                                     fileType: fileMetadata.fileType,
                                                     fileLocation: fileMetadata.fileLocation)
                            } else if let groupMetadata = entity.customMetadata {
                                // It's a group entity
                                await model.openGroup(label: groupMetadata.label,
                                                      color: groupMetadata.color,
                                                      materialName: groupMetadata.materialName,
                                                      files: groupMetadata.files.map { [
                                                          "label": $0.label,
                                                          "fileType": $0.fileType,
                                                          "preview": $0.preview,
                                                          "fileLocation": $0.fileLocation
                                                      ] })
                            }
                        }
                    }
                }
        )
        .gesture(
            // Enable pinch to drag on these items
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    if let entity = value.entity as? ModelEntity {
                        entity.position = value.convert(value.location3D, from: .local, to: entity.parent!)
                    }
                }
        )
        .onDisappear {
//            print("📦 StackingView disappeared — cleaning up preview window")
            appModel.previewedFile = nil
            dismissWindow(id: "FilePreview")
        }
    }
}

//#Preview {
//    StackingView()
//}
