import RealityKit
import Foundation
import SwiftUI
import RealityKitContent

// Helper function to extract the first material from a ModelEntity inside a USD file
func extractMaterial(fromUSDNamed usdName: String, entityName: String) throws -> RealityKit.Material {
    let loadedEntity = try Entity.load(named: usdName, in: realityKitContentBundle)
    guard let modelEntity = loadedEntity.findEntity(named: entityName) as? ModelEntity,
          let material = modelEntity.model?.materials.first else {
        throw NSError(domain: "MaterialError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Material not found in \(usdName) -> \(entityName)"])
    }
    return material
}

struct AuraView: View {
    @StateObject var model = HandTrackingViewModel()
    
    var body: some View {
        RealityView { content in
            // Add hand tracking content
            content.add(model.setupContentEntity())
            
            // Your base mesh (assumed created elsewhere)
            let baseAuraMesh = MeshResource.generateSphere(radius: 0.1)

            // Extract the material from aura.usda
            do {
                let auraMaterial = try extractMaterial(fromUSDNamed: "Aura", entityName: "Sphere")

                // Create your new ModelEntity with the mesh and the extracted material
                let files = ModelEntity(mesh: baseAuraMesh, materials: [auraMaterial])
                files.components.set(InputTargetComponent(allowedInputTypes: .indirect))
                files.generateCollisionShapes(recursive: true)
                files.components.set(GroundingShadowComponent(castsShadow: true))
                
                // Add physics with dynamic mode so it falls onto the table
                let physicsMaterial = PhysicsMaterialResource.generate(friction: 0.8, restitution: 0.1)

                files.components.set(
                    PhysicsBodyComponent(
                        shapes: [.generateSphere(radius: 0.1)],
                        mass: 0.5,
                        material: physicsMaterial,
                        mode: .dynamic
                    )
                )
                
                // Start above so gravity pulls it down
                files.setPosition(SIMD3<Float>(0, 2, -0.5), relativeTo: nil)
                
                content.add(files)

            } catch {
                print("Failed to load aura material: \(error)")
            }
        }
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    if let entity = value.entity as? ModelEntity {
                        entity.position = value.convert(value.location3D, from: .local, to: entity.parent!)
                    }
                }
        )
        .task {
            // Run ARKit Session (track environment)
            await model.runSession()
        }.task {
            // process our world reconstruction
            await model.processReconstructionUpdates()
        }
    }
}

#Preview("Immersive Style", immersionStyle: .automatic) {
    AuraView()
}
