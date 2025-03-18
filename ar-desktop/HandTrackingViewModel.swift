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
        named meshName: String = "DefaultMesh",
        materialName: String = "DefaultMaterial",
        label: String = "Untitled",
        color: Color = .blue
    ) async {
        guard let leftFingerPosition = fingerEntities[.left]?.transform.translation else { return }
        let placementLocation = leftFingerPosition + SIMD3<Float>(0, -0.05, 0)

        // LOAD MESH
        var meshResource: MeshResource
        if meshName == "DefaultMesh" {
            meshResource = .generateSphere(radius: 0.1)
        } else {
            do {
                let loadedEntity = try await Entity(named: meshName, in: realityKitContentBundle)
                if let modelEntity = loadedEntity as? ModelEntity, let modelMesh = modelEntity.model?.mesh {
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
        // TODO: Apply color tint to loaded material
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
        object.setPosition(placementLocation, relativeTo: nil)
        object.components.set(InputTargetComponent(allowedInputTypes: .indirect))
        object.generateCollisionShapes(recursive: true)
        object.components.set(GroundingShadowComponent(castsShadow: true))

        // Add physics with dynamic mode so it falls onto the table
        let physicsMaterial = PhysicsMaterialResource.generate(friction: 0.8, restitution: 0.1)
        object.components.set(
            PhysicsBodyComponent(
                shapes: object.collision!.shapes,
                mass: 0.5,
                material: physicsMaterial,
                mode: .dynamic
            )
        )

        contentEntity.addChild(object)
    }
    
    //////////////////////////


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
    
}
