//
//  HandTrackingViewModel.swift
//  ar-desktop
//
//  Created by Gary Smith on 2/23/25.
//

import Foundation
import RealityKit
import SwiftUI
import ARKit
import RealityKitContent
import UIKit
import PDFKit

import Combine

struct LabelComponent: Component {
    var text: String
    var color: UIColor
}

@MainActor class HandTrackingViewModel: ObservableObject {
    @Published var objectsPlaced: Int = 0
    @Published var desktopCenter: SIMD3<Float> = SIMD3<Float>(0, 0, 0)

    // Hand tracking
    private let session = ARKitSession()
    private let handTracking = HandTrackingProvider()
    private let worldTracking = WorldTrackingProvider()
    
    // Detecting funiture, tables, etc
    private let sceneReconstruction = SceneReconstructionProvider()
    
    private var contentEntity = Entity()
    
    // storing the meshes we create for scene reconstruction
    private var meshEntities = [UUID : ModelEntity]()
    
    private let fingerEntities: [HandAnchor.Chirality : ModelEntity] = [
        .left: .createFingertip(),
        .right: .createFingertip()
    ]
    
    // To not place too many cubes at a time
    private var lastCuvePlacementTime: TimeInterval = 0

    private let didPinchSubject = PassthroughSubject<Void, Never>()

    var didPinchStream: AsyncStream<Void> {
        AsyncStream { continuation in
            let cancellable = didPinchSubject.sink { _ in
                continuation.yield()
            }
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
    
    
    // FUNCTIONS

    func showLabel(for object: ModelEntity, with text: String, color theColor: UIColor, height: Float = 0.2) async {
        let textMesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.01,
            font: .systemFont(ofSize: 0.2),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        
        let textMaterial = UnlitMaterial(color: .black)
        let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
        textEntity.scale = SIMD3<Float>(repeating: 0.05)
        
        let textBounds = textMesh.bounds.extents
        let backgroundWidth = textBounds.x * 0.2
        let backgroundHeight = textBounds.y * 0.3
        
        let transparentColor = theColor.withAlphaComponent(0.0)
        var backgroundMaterial = SimpleMaterial(color: transparentColor, isMetallic: false)
        let backgroundEntity = ModelEntity(
            mesh: .generatePlane(width: backgroundWidth, height: backgroundHeight, cornerRadius: 0.01),
            materials: [backgroundMaterial]
        )
        
        let textCenterOffset = SIMD3<Float>(
            -textBounds.x * textEntity.scale.x,
            -textBounds.y * textEntity.scale.y,
            0.001
        )
        textEntity.setPosition(textCenterOffset, relativeTo: backgroundEntity)
        textEntity.scale = SIMD3<Float>(repeating: 0.1)
        backgroundEntity.addChild(textEntity)
        
        backgroundEntity.components.set(BillboardComponent())
        contentEntity.addChild(backgroundEntity)
        
        let objectWorldPos = object.position(relativeTo: nil)
        let offset = SIMD3<Float>(0, height, 0)
        backgroundEntity.setPosition(objectWorldPos + offset, relativeTo: nil)

        // Fade in
        await animateAlpha(of: backgroundEntity, from: 0.0, to: 0.5, duration: 0.15)

        // Wait 3 seconds
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        // Fade out
        await animateAlpha(of: backgroundEntity, from: 0.5, to: 0.0, duration: 0.15)

        // Remove from scene
        backgroundEntity.removeFromParent()
    }

    func animateAlpha(of entity: ModelEntity, from startAlpha: CGFloat, to endAlpha: CGFloat, duration: TimeInterval) async {
        guard var material = entity.model?.materials.first as? SimpleMaterial else { return }

        let steps = 30
        let delay = duration / Double(steps)

        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let alpha = startAlpha + (endAlpha - startAlpha) * t
            var color = material.color.tint
            color = color.withAlphaComponent(alpha)

            material.color = .init(tint: color)
            entity.model?.materials = [material]

            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
    
    func setupContentEntity() -> Entity {
        // Add fingertips
        for entity in fingerEntities.values {
            contentEntity.addChild(entity)
        }
        return contentEntity
    }
    
    func runSession() async {
        do {
            try await session.run([sceneReconstruction, handTracking, worldTracking])
            
            // RUN GAZE TRACKING
            Task {
                await runGazeDetectionLoop()
            }
        } catch {
            print ("failed to start session: \(error)")
        }
    }
    
    func processHandUpdates() async {
        // Iterates through its updates
        for await update in handTracking.anchorUpdates {
            let handAnchor = update.anchor
            
            guard handAnchor.isTracked else { continue }
            
            let fingerTip = handAnchor.handSkeleton?.joint(.indexFingerTip)
            
            guard ((fingerTip?.isTracked) != nil) else { continue }
            
            // know we now have a tracked finger...
            let originFromWrist = handAnchor.originFromAnchorTransform
            let wristFromIndex = fingerTip?.anchorFromJointTransform
            let originFromIndex = originFromWrist * wristFromIndex!
            
            // position finger entities
            fingerEntities[handAnchor.chirality]?.setTransformMatrix(originFromIndex, relativeTo: nil)
            
            if handAnchor.chirality == .right {
                if let thumb = handAnchor.handSkeleton?.joint(.thumbTip),
                   let index = handAnchor.handSkeleton?.joint(.indexFingerTip),
                   thumb.isTracked, index.isTracked {

                    let thumbPos = simd_make_float3(handAnchor.originFromAnchorTransform * thumb.anchorFromJointTransform.columns.3)
                    let indexPos = simd_make_float3(handAnchor.originFromAnchorTransform * index.anchorFromJointTransform.columns.3)

                    let distance = simd_distance(thumbPos, indexPos)
                    let now = Date().timeIntervalSince1970
                    if distance < 0.02 && now - lastCuvePlacementTime > 1.0 {
                        lastCuvePlacementTime = now
                        didPinchSubject.send()
                    }
                }
            }
        }
    }
    
    func processReconstructionUpdates() async {
        for await update in sceneReconstruction.anchorUpdates {
            // make a shape of the environment / desktop
            guard let shape = try? await
                    ShapeResource.generateStaticMesh(from: update.anchor) else { continue }
            // switching through events
            switch update.event {
            case .added:
                let entity = ModelEntity()
                entity.transform = Transform(matrix: update.anchor.originFromAnchorTransform)
                entity.collision = CollisionComponent(shapes: [shape], isStatic: true)
                // make it possible to add physics
                entity.physicsBody = PhysicsBodyComponent()
                // make it interactible
                entity.components.set(InputTargetComponent())
                
                // update mesh when doing more scene reconstructions
                meshEntities[update.anchor.id] = entity
                contentEntity.addChild(entity)
                
            case .updated:
                guard let entity = meshEntities[update.anchor.id] else { fatalError("Oh no!") }
                entity.transform = Transform(matrix: update.anchor.originFromAnchorTransform)
                entity.collision?.shapes = [shape]
                
            case .removed:
                meshEntities[update.anchor.id]?.removeFromParent()
                meshEntities.removeValue(forKey: update.anchor.id)
            }
        }
    }

    
    //////////////////////////
    
    // Helper function to extract the first material from a ModelEntity inside a USD file
    func extractMaterial(fromUSDNamed usdName: String, entityName: String) async throws -> RealityKit.Material {
        let loadedEntity = try await Entity(named: usdName, in: realityKitContentBundle)
        guard let modelEntity = loadedEntity.findEntity(named: entityName) as? ModelEntity,
              let material = modelEntity.model?.materials.first else {
            throw NSError(domain: "MaterialError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Material not found in \(usdName) -> \(entityName)"])
        }
        return material
    }
    
    // FUNCTION FOR PLACING THE FOLDERS/GROUPING OBJECTS
    func placeObject(
        meshName: String = "DefaultMesh",
        materialName: String = "DefaultMaterial",
        label: String = "Untitled",
        color: Color = .blue
    ) async -> ModelEntity? {
        // add to this objectsPlaced count
        objectsPlaced += 1
        
        guard let leftFingerPosition = fingerEntities[.left]?.transform.translation else { return nil }
        let placementLocation = leftFingerPosition + SIMD3<Float>(0, -0.05, 0)
        
        // LOAD MESH
        var meshResource: MeshResource
        if meshName == "DefaultMesh" {
            meshResource = .generateSphere(radius: 0.075)
        } else {
            do {
                let loadedEntity = try await Entity(named: meshName, in: realityKitContentBundle)
                print("Loaded entity hierarchy for \(meshName):")

                if let modelEntity = loadedEntity.children.recursiveCompactMap({ $0 as? ModelEntity }).first,
                   let modelMesh = modelEntity.model?.mesh {
                    meshResource = modelMesh
                } else {
                    print("Failed to extract mesh from \(meshName), using default sphere")
                    meshResource = .generateSphere(radius: 0.075)
                }
            } catch {
                print("Error loading mesh: \(error), using default sphere")
                meshResource = .generateSphere(radius: 0.075)
            }
        }
        
        // LOAD MATERIAL
        var material: RealityKit.Material
        if materialName == "DefaultMaterial" {
            material = SimpleMaterial(color: UIColor(color), isMetallic: false)
        } else {
            do {
                material = try await extractMaterial(fromUSDNamed: materialName, entityName: "Geometry")
            } catch {
                print("Error loading material: \(error), using default material")
                material = SimpleMaterial(color: UIColor(color), isMetallic: false)
            }
        }
        
        // ADD BASIC OBJECT STUFF
        let object = ModelEntity(mesh: meshResource, materials: [material])
        // scale it way down
        object.scale = SIMD3<Float>(repeating: Float(0.001))
        // rotate it upwards
        let rotation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        object.transform.rotation = rotation
        
        
        contentEntity.addChild(object)
        object.setPosition(placementLocation, relativeTo: nil)
        object.components.set(InputTargetComponent(allowedInputTypes: .indirect))
        object.generateCollisionShapes(recursive: true)
        object.components.set(GroundingShadowComponent(castsShadow: true))

        // Example usage: Show label when object is placed
        Task {
            await showLabel(for: object, with: label, color: UIColor(color), height: 0.1)
            // Gaze Tracking Label
            object.components.set(LabelComponent(text: label, color: UIColor(color).withAlphaComponent(0.5)))
        }

        // Add physics with dynamic mode so it falls onto the table
        let physicsMaterial = PhysicsMaterialResource.generate(friction: 0.8, restitution: 0.1)
        object.components.set(
            PhysicsBodyComponent(
                shapes: object.collision!.shapes,
                mass: 10,
                material: physicsMaterial,
                mode: .dynamic
            )
        )
        object.physicsBody?.linearDamping = 10.0
        object.physicsBody?.angularDamping = 10.0
        
        // add hover glisten effect
        object.components.set(HoverEffectComponent())
        
        return object
    }
    
    
    //////////////////////////
    

//    private func findTableSurface(near point: SIMD3<Float>) -> ModelEntity? {
//        var closestEntity: ModelEntity? = nil
//        var minHorizontalDistance: Float = Float.greatestFiniteMagnitude
//
//        for entity in meshEntities.values {
//            let upVector = simd_act(entity.transform.rotation, SIMD3<Float>(0, 1, 0))
//            if abs(upVector.y) > 0.9 {  // Flat surface check
//                let boundsCenter = entity.visualBounds(relativeTo: nil).center
//                let dx = boundsCenter.x - point.x
//                let dz = boundsCenter.z - point.z
//                let horizontalDistance = sqrt(dx * dx + dz * dz)
//
//                if horizontalDistance < minHorizontalDistance {
//                    minHorizontalDistance = horizontalDistance
//                    closestEntity = entity
//                }
//            }
//        }
//
//        return closestEntity
//    }
    
    // Add a property to track the current open group
    private var currentGroupEntity: Entity?
    
    func openGroup(
        label: String = "Untitled",
        color: Color = .blue,
        materialName: String = "DefaultMaterial",
        // Each file is a dictionary with keys: "label", "fileType", "fileLocation"
        files: [[String: String]] = []
    ) async {
        // If a group is already open, remove it
        currentGroupEntity?.removeFromParent()
        currentGroupEntity = nil

        // Create a highlight entity as a plane (dimensions 4 x 5 units) for now;
        // later, you can modify this to generate an oval shape
        let highlightWidth: Float = 2.5/6
        let highlightDepth: Float = 1.5/6
        let highlightMesh = MeshResource.generatePlane(width: highlightWidth, depth: highlightDepth)
        
        // Create a simple material for the highlight. Later you can add custom loading logic based on materialName.
        // LOAD MATERIAL
        var material: RealityKit.Material
        if materialName == "DefaultMaterial" {
            material = SimpleMaterial(color: UIColor(color), isMetallic: false)
        } else {
            do {
                let trimmedMaterialName = String(materialName.dropLast(3))
                material = try await extractMaterial(fromUSDNamed: trimmedMaterialName, entityName: "Sphere")
            } catch {
                print("Error loading material: \(error), using default colored material")
                material = SimpleMaterial(color: UIColor(color), isMetallic: false)
            }
        }
        
        let highlightEntity = ModelEntity(mesh: highlightMesh, materials: [material])
        highlightEntity.setPosition(desktopCenter, relativeTo: nil)
        highlightEntity.generateCollisionShapes(recursive: true)
        highlightEntity.components.set(PhysicsBodyComponent(mode: .static))
        
        let groupContainer = Entity()
        contentEntity.addChild(groupContainer)
        currentGroupEntity = groupContainer
        
        groupContainer.addChild(highlightEntity)
        
        // Add a label above this highlight, also along the table -- the background can be of color color
//        Task {
//            await showLabel(for: highlightEntity, with: label, color: UIColor(color).withAlphaComponent(0.5))
//        }
        
        // Arrange file icons in a grid within the highlight area
        let fileCount = files.count
        let columns = min(fileCount, 3)
        let rows = Int(ceil(Double(fileCount) / Double(columns)))
        
        for (index, fileDict) in files.enumerated() {
            let col = index % columns
            let row = index / columns
            let cellWidth = highlightWidth / Float(columns)
            let cellDepth = highlightDepth / Float(rows)
            let xOffset = (Float(col) - Float(columns - 1) / 2) * cellWidth
            let zOffset = (Float(row) - Float(rows - 1) / 2) * cellDepth

            let filePosition = SIMD3<Float>(xOffset, 0.02, zOffset)
            
            let fileMesh = MeshResource.generateBox(size: SIMD3<Float>(0.08, 0.002, 0.08))
            let fileMaterial = SimpleMaterial(color: .gray, isMetallic: true)
            let fileEntity = ModelEntity(mesh: fileMesh, materials: [fileMaterial])
            
            
            // Enable input and physics
            fileEntity.components.set(InputTargetComponent(allowedInputTypes: .indirect))
            fileEntity.generateCollisionShapes(recursive: true)
            
            let physicsMaterial = PhysicsMaterialResource.generate(friction: 0.8, restitution: 0.1)
            fileEntity.components.set(
                PhysicsBodyComponent(
                    shapes: fileEntity.collision!.shapes,
                    mass: 1.0,
                    material: physicsMaterial,
                    mode: .dynamic
                )
            )
            fileEntity.physicsBody?.linearDamping = 10.0
            fileEntity.physicsBody?.angularDamping = 10.0
            fileEntity.components.set(GroundingShadowComponent(castsShadow: true))
            fileEntity.components.set(HoverEffectComponent())
            
            // Add preview image if present
            if let previewName = fileDict["fileLocation"],
               let image = UIImage(named: previewName),
               let cgImage = image.cgImage,
               let textureResource = try? await TextureResource(image: cgImage, options: .init(semantic: nil)) {
                
                var previewMaterial = PhysicallyBasedMaterial()

                previewMaterial.baseColor = PhysicallyBasedMaterial.BaseColor(
                    tint: .white,
                    texture: .init(textureResource)
                )

                let previewPlane = ModelEntity(
                    mesh: .generatePlane(width: 0.075, height: 0.075),
                    materials: [previewMaterial]
                )

                fileEntity.addChild(previewPlane)

                let previewOffset = SIMD3<Float>(0, 0.003, 0)
                previewPlane.setPosition(previewOffset, relativeTo: fileEntity)

                let upwardRotation = simd_quatf(angle: -Float.pi/2, axis: SIMD3<Float>(1, 0, 0))
                previewPlane.transform.rotation = upwardRotation
            }
            
            // Add label if present
            if let fileLabel = fileDict["label"] {
//                Task {
//                    await self.showLabel(for: fileEntity, with: fileLabel, color: UIColor(.white).withAlphaComponent(0.8))
//                }
                // GazeTracking Label
                fileEntity.components.set(LabelComponent(text: fileLabel, color: .white.withAlphaComponent(0.5)))
                
            }
            
            
            
            
            highlightEntity.addChild(fileEntity)
            
            fileEntity.setPosition(filePosition, relativeTo: highlightEntity) // Position relative to the highlight, not world space
            fileEntity.transform.rotation = simd_quatf()
        }
    }
    
    
    //////////////////////////
    
    func collectDesktopCenterOnPinch() async -> SIMD3<Float>? {
        // 0.5-second delay before starting
        try? await Task.sleep(nanoseconds: 500_000_000)
        // 2 seconds in nanoseconds
        let timeout: UInt64 = 2_000_000_000
        // check every 0.1 second
        let interval: UInt64 = 100_000_000
        var elapsed: UInt64 = 0

        while elapsed < timeout {
            if let leftFingerTip = fingerEntities[.left]?.transform.translation,
               leftFingerTip != SIMD3<Float>(0, 0, 0) {
                print("✅ Desktop center set at: \(leftFingerTip)")
                self.desktopCenter = leftFingerTip
                return leftFingerTip
            }
            try? await Task.sleep(nanoseconds: interval)
            elapsed += interval
        }

        print("⚠️ Left finger still at 0,0,0 after waiting for 2 seconds")
        return nil
    }
    
    // GAZE TRACKING
    func runGazeDetectionLoop() async {
        // Wait for world tracking to be running
        while worldTracking.state != .running {
            print("⏳ Waiting for worldTracking to start...")
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        print("✅ worldTracking is now running. Starting gaze detection loop.")
        
        var lastLabelShownTime: TimeInterval = 0
        let labelCooldown: TimeInterval = 0

        while true {
            if let transform = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime())?.originFromAnchorTransform {
                let cameraPosition = simd_make_float3(transform.columns.3)
                let pitchDownAngle: Float = -.pi / 14  // ~13 degrees downward offset
                let right = simd_make_float3(transform.columns.0)
                let downwardRotation = simd_quatf(angle: pitchDownAngle, axis: right)
                var forward = -simd_make_float3(transform.columns.2)
                forward = simd_normalize(downwardRotation.act(forward))

                if let result = contentEntity.scene?.raycast(origin: cameraPosition, direction: forward, length: 2.0).first {
                    let entity = result.entity
                    print("👁 Gaze hit entity: \(entity.name)")
                    if let labelComponent = entity.components[LabelComponent.self] {
                        let currentTime = Date().timeIntervalSince1970
                        if currentTime - lastLabelShownTime > labelCooldown {
                            lastLabelShownTime = currentTime
                            print("🟢 LabelComponent found: \(labelComponent.text)")
                            await showLabel(for: entity as! ModelEntity, with: labelComponent.text, color: labelComponent.color, height: 0.1)
                        } else {
                            print("⏸ Label cooldown active")
                        }
                    } else {
                        print("⚠️ No LabelComponent on hit entity")
                    }
                } else {
                    print("👁 Nothing hit by gaze raycast")
                }
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }
}

extension Collection where Element == Entity {
    func recursiveCompactMap<T>(_ transform: (Entity) -> T?) -> [T] {
        var result: [T] = []
        for entity in self {
            if let transformed = transform(entity) {
                result.append(transformed)
            }
            result.append(contentsOf: entity.children.recursiveCompactMap(transform))
        }
        return result
    }
}




//func imageFromPDF(url: URL) -> UIImage? {
//    guard let document = PDFDocument(url: url),
//          let page = document.page(at: 0) else {
//        print("Failed to load PDF")
//        return nil
//    }
//
//    let pageRect = page.bounds(for: .mediaBox)
//    let renderer = UIGraphicsImageRenderer(size: pageRect.size)
//
//    // Create the image with proper orientation
//    let image = renderer.image { context in
//        // Clear the background with white
//        UIColor.white.set()
//        context.fill(pageRect)
//
//        // Save the graphics state
//        context.cgContext.saveGState()
//
//        // Flip the context vertically to correct the orientation
//        // PDFs have origin at bottom-left, UIKit has origin at top-left
//        context.cgContext.translateBy(x: 0, y: pageRect.size.height)
//        context.cgContext.scaleBy(x: 1.0, y: -1.0)
//
//        // Draw the PDF page in the properly transformed context
//        page.draw(with: .mediaBox, to: context.cgContext)
//
//        // Restore the graphics state
//        context.cgContext.restoreGState()
//    }
//
//    return image
//}



//func placeFile(named filename: String) async {
//    guard let leftFingerPosition = fingerEntities[.left]?.transform.translation else { return }
//    let placementLocation = leftFingerPosition + SIMD3<Float>(0, -0.05, 0)
//
//    // Load PDF and generate image with corrected orientation
//    guard let pdfURL = Bundle.main.url(forResource: filename, withExtension: "pdf"),
//          let pdfImage = imageFromPDF(url: pdfURL),
//          let cgImage = pdfImage.cgImage else {
//        print("PDF processing error")
//        return
//    }
//
//    // Create a texture from the PDF image
//    guard let textureResource = try? await TextureResource(image: cgImage, options: .init(semantic: nil)) else {
//        print("Texture conversion error")
//        return
//    }
//
//    var textMaterial = UnlitMaterial()
//    textMaterial.color = .init(tint: .white, texture: .init(textureResource))
//
//    // Match box proportions to PDF aspect
//    let imageSize = pdfImage.size
//    let aspectRatio = imageSize.height / imageSize.width
//    let desiredWidth: Float = 0.2
//    let desiredHeight: Float = desiredWidth * Float(aspectRatio)
//
//    // "Paper" box
//    let fileEntity = ModelEntity(
//        mesh: .generateBox(size: SIMD3<Float>(desiredWidth, 0.002, desiredHeight)),
//        materials: [SimpleMaterial(color: .white, isMetallic: false)],
//        collisionShape: .generateBox(size: SIMD3<Float>(desiredWidth, 0.002, desiredHeight)),
//        mass: 1.0
//    )
//    fileEntity.setPosition(placementLocation, relativeTo: nil)
//
//    // PDF plane
//    let textPlane = ModelEntity(
//        mesh: .generatePlane(width: desiredWidth, height: desiredHeight),
//        materials: [textMaterial]
//    )
//    fileEntity.addChild(textPlane)
//
//    // Position the plane slightly above the top face of the box
//    textPlane.setPosition(SIMD3<Float>(0, 0.0011, 0), relativeTo: fileEntity)
//
//    // Rotate the plane to face upward
//    textPlane.transform.rotation = simd_quatf(angle: -Float.pi/2, axis: SIMD3<Float>(1, 0, 0))
//
//    contentEntity.addChild(fileEntity)
//}

//     Example gaze detection trigger:
//    func onGaze(at object: ModelEntity, label: String) async {
//         await showLabel(for: object, with: label)
//    }
//
//    func collectDesktopCenterOnPinch() async -> SIMD3<Float>? {
//        for await update in handTracking.anchorUpdates {
//            let handAnchor = update.anchor
//            guard handAnchor.isTracked, handAnchor.chirality == .right else { continue }
//
//            let thumbTip = handAnchor.handSkeleton?.joint(.thumbTip)
//            let indexTip = handAnchor.handSkeleton?.joint(.indexFingerTip)
//
//            if let thumb = thumbTip, let index = indexTip,
//               thumb.isTracked, index.isTracked {
//                let thumbPos = simd_make_float3(handAnchor.originFromAnchorTransform * thumb.anchorFromJointTransform.columns.3)
//                let indexPos = simd_make_float3(handAnchor.originFromAnchorTransform * index.anchorFromJointTransform.columns.3)
//
//                let distance = simd_distance(thumbPos, indexPos)
//                if distance < 0.02 { // Pinch detected
//                    if let leftFingerTip = fingerEntities[.left]?.transform.translation {
//                        print("✅ Desktop center set at: \(leftFingerTip)")
//                        return leftFingerTip
//                    }
//                }
//            }
//        }
//        return nil
//    }
