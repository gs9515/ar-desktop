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

@MainActor class HandTrackingViewModel: ObservableObject {
    @Published var objectsPlaced: Int = 0

    // Hand tracking
    private let session = ARKitSession()
    private let handTracking = HandTrackingProvider()
    
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
    
    
    // FUNCTIONS

    // Reusable floating label function using RealityKit's generateText with background
    func showLabel(for object: ModelEntity, with text: String, color theColor: UIColor) async {
        // Generate vector-based text mesh with larger font
        let textMesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.01,
            font: .systemFont(ofSize: 0.2),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        
        // Create unlit material for clear readability
        let textMaterial = UnlitMaterial(color: .black)
        let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
        textEntity.scale = SIMD3<Float>(repeating: 0.05)
        
        // Compute text bounds to size background plane
        let textBounds = textMesh.bounds.extents
        let backgroundWidth = textBounds.x * 0.2
        let backgroundHeight = textBounds.y * 0.3
        
        // Create background plane
        let backgroundMesh = MeshResource.generatePlane(width: backgroundWidth, height: backgroundHeight)
        let backgroundMaterial = UnlitMaterial(color: theColor)
        let backgroundEntity = ModelEntity(mesh: backgroundMesh, materials: [backgroundMaterial])
        if var modelComponent = backgroundEntity.model {
            modelComponent.mesh = .generatePlane(width: backgroundWidth, height: backgroundHeight, cornerRadius: 0.01)
            backgroundEntity.model = modelComponent
        }
        
        // Adjust text position to center on background
        let textCenterOffset = SIMD3<Float>(
            -textBounds.x * textEntity.scale.x,
            -textBounds.y * textEntity.scale.y,
            0.001
        )
        textEntity.setPosition(textCenterOffset, relativeTo: backgroundEntity)
        // Add text as child of background and adjust scale
        textEntity.scale = SIMD3<Float>(repeating: 0.1)
        backgroundEntity.addChild(textEntity)
        
        backgroundEntity.components.set(BillboardComponent())
        contentEntity.addChild(backgroundEntity)
        
        // Animate label following the object
        Task {
            var timeElapsed: UInt64 = 0
            while timeElapsed < 3_000_000_000 {
                let objectWorldPos = object.position(relativeTo: nil)
                let offset = SIMD3<Float>(0, 0.2, 0)
                backgroundEntity.setPosition(objectWorldPos + offset, relativeTo: nil)
                try? await Task.sleep(nanoseconds: 33_000_000) // ~30fps
                timeElapsed += 33_000_000
            }
            backgroundEntity.removeFromParent()
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
            try await session.run([sceneReconstruction, handTracking])
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
    
    func placeObject(
        meshName: String = "DefaultMesh",
        materialName: String = "DefaultMaterial",
        label: String = "Untitled",
        color: Color = .blue
    ) async {
        // add to this objectsPlaced count
        objectsPlaced += 1
        
        guard let leftFingerPosition = fingerEntities[.left]?.transform.translation else { return }
        let placementLocation = leftFingerPosition + SIMD3<Float>(0, -0.05, 0)
        
        // LOAD MESH
        var meshResource: MeshResource
        if meshName == "DefaultMesh" {
            meshResource = .generateSphere(radius: 0.1)
        } else {
            do {
                let loadedEntity = try await Entity(named: meshName, in: realityKitContentBundle)
                print("Loaded entity hierarchy for \(meshName):")

                if let modelEntity = loadedEntity.children.recursiveCompactMap({ $0 as? ModelEntity }).first,
                   let modelMesh = modelEntity.model?.mesh {
                    meshResource = modelMesh
                } else {
                    print("Failed to extract mesh from \(meshName), using default sphere")
                    meshResource = .generateSphere(radius: 0.1)
                }
            } catch {
                print("Error loading mesh: \(error), using default sphere")
                meshResource = .generateSphere(radius: 0.1)
            }
        }
        
        // LOAD MATERIAL
        var material: RealityKit.Material
        if materialName == "DefaultMaterial" {
            material = SimpleMaterial(color: UIColor(color), isMetallic: false)
        } else {
            do {
                material = try await extractMaterial(fromUSDNamed: materialName, entityName: "Sphere")
            } catch {
                print("Error loading material: \(error), using default blue material")
                material = SimpleMaterial(color: UIColor(color), isMetallic: false)
            }
        }
        
        // ADD BASIC OBJECT STUFF
        let object = ModelEntity(mesh: meshResource, materials: [material])
//        object.scale = SIMD3<Float>(repeating: 0.1) // Or any small factor
        object.setPosition(placementLocation, relativeTo: nil)
        object.components.set(InputTargetComponent(allowedInputTypes: .indirect))
        object.generateCollisionShapes(recursive: true)
        object.components.set(GroundingShadowComponent(castsShadow: true))

        // Example usage: Show label when object is placed
        Task {
            await showLabel(for: object, with: label, color: UIColor(color).withAlphaComponent(0.5))
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
        object.physicsBody?.linearDamping = 5.0
        object.physicsBody?.angularDamping = 5.0
        
        // add hover glisten effect
        object.components.set(HoverEffectComponent())
        
        contentEntity.addChild(object)
    }
    
    
    //////////////////////////
    
    
    func imageFromPDF(url: URL) -> UIImage? {
        guard let document = PDFDocument(url: url),
              let page = document.page(at: 0) else {
            print("Failed to load PDF")
            return nil
        }
        
        let pageRect = page.bounds(for: .mediaBox)
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        
        // Create the image with proper orientation
        let image = renderer.image { context in
            // Clear the background with white
            UIColor.white.set()
            context.fill(pageRect)
            
            // Save the graphics state
            context.cgContext.saveGState()
            
            // Flip the context vertically to correct the orientation
            // PDFs have origin at bottom-left, UIKit has origin at top-left
            context.cgContext.translateBy(x: 0, y: pageRect.size.height)
            context.cgContext.scaleBy(x: 1.0, y: -1.0)
            
            // Draw the PDF page in the properly transformed context
            page.draw(with: .mediaBox, to: context.cgContext)
            
            // Restore the graphics state
            context.cgContext.restoreGState()
        }
        
        return image
    }
    
    func placeFile(named filename: String) async {
        guard let leftFingerPosition = fingerEntities[.left]?.transform.translation else { return }
        let placementLocation = leftFingerPosition + SIMD3<Float>(0, -0.05, 0)
        
        // Load PDF and generate image with corrected orientation
        guard let pdfURL = Bundle.main.url(forResource: filename, withExtension: "pdf"),
              let pdfImage = imageFromPDF(url: pdfURL),
              let cgImage = pdfImage.cgImage else {
            print("PDF processing error")
            return
        }
        
        // Create a texture from the PDF image
        guard let textureResource = try? await TextureResource(image: cgImage, options: .init(semantic: nil)) else {
            print("Texture conversion error")
            return
        }
        
        var textMaterial = UnlitMaterial()
        textMaterial.color = .init(tint: .white, texture: .init(textureResource))
        
        // Match box proportions to PDF aspect
        let imageSize = pdfImage.size
        let aspectRatio = imageSize.height / imageSize.width
        let desiredWidth: Float = 0.2
        let desiredHeight: Float = desiredWidth * Float(aspectRatio)
        
        // "Paper" box
        let fileEntity = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(desiredWidth, 0.002, desiredHeight)),
            materials: [SimpleMaterial(color: .white, isMetallic: false)],
            collisionShape: .generateBox(size: SIMD3<Float>(desiredWidth, 0.002, desiredHeight)),
            mass: 1.0
        )
        fileEntity.setPosition(placementLocation, relativeTo: nil)
        
        // PDF plane
        let textPlane = ModelEntity(
            mesh: .generatePlane(width: desiredWidth, height: desiredHeight),
            materials: [textMaterial]
        )
        fileEntity.addChild(textPlane)
        
        // Position the plane slightly above the top face of the box
        textPlane.setPosition(SIMD3<Float>(0, 0.0011, 0), relativeTo: fileEntity)
        
        // Rotate the plane to face upward
        textPlane.transform.rotation = simd_quatf(angle: -Float.pi/2, axis: SIMD3<Float>(1, 0, 0))
        
        contentEntity.addChild(fileEntity)
    }
    
    // Example gaze detection trigger:
//    func onGaze(at object: ModelEntity, label: String) async {
//         await showLabel(for: object, with: label)
//    }
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
