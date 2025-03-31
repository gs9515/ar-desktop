import RealityKit
import UIKit

enum RoundedPhotoEntityFactory {
    
    static func createFileWithPreviewEntity(
        previewImageName: String? = nil,
        size: SIMD3<Float> = SIMD3<Float>(0.08, 0.002, 0.08),
        color: UIColor = .gray,
        previewSize: Float = 0.075,
        cornerRadius: Float = 0.01
    ) async -> ModelEntity {
        let fileMesh = await MeshResource.generateBox(size: SIMD3<Float>(0.08, 0.002, 0.08))
        let fileMaterial = SimpleMaterial(color: .gray, isMetallic: true)
        let fileEntity = await ModelEntity(mesh: fileMesh, materials: [fileMaterial])
        
        
        // Enable input and physics
        await fileEntity.components.set(InputTargetComponent(allowedInputTypes: .indirect))
        await fileEntity.generateCollisionShapes(recursive: true)
        
        let physicsMaterial = await PhysicsMaterialResource.generate(friction: 0.8, restitution: 0.1)
        await fileEntity.components.set(
            PhysicsBodyComponent(
                shapes: fileEntity.collision!.shapes,
                mass: 1.0,
                material: physicsMaterial,
                mode: .dynamic
            )
        )
        await MainActor.run {
            fileEntity.physicsBody?.linearDamping = 10.0
            fileEntity.physicsBody?.angularDamping = 10.0
        }
        await fileEntity.components.set(GroundingShadowComponent(castsShadow: true))
        await fileEntity.components.set(HoverEffectComponent())
        
        // Add preview image if present
        if let previewImageName,
           let image = UIImage(named: previewImageName),
           let cgImage = image.cgImage,
           let textureResource = try? await TextureResource(image: cgImage, options: .init(semantic: nil)) {
            
            var previewMaterial = PhysicallyBasedMaterial()
            
            previewMaterial.baseColor = PhysicallyBasedMaterial.BaseColor(
                tint: .white,
                texture: .init(textureResource)
            )
            
            let previewPlane = await ModelEntity(
                mesh: .generatePlane(width: 0.075, height: 0.075),
                materials: [previewMaterial]
            )
            
            await fileEntity.addChild(previewPlane)
            
            let previewOffset = SIMD3<Float>(0, 0.003, 0)
            await previewPlane.setPosition(previewOffset, relativeTo: fileEntity)
            
            let upwardRotation = simd_quatf(angle: -Float.pi/2, axis: SIMD3<Float>(1, 0, 0))
            await MainActor.run {
                previewPlane.transform.rotation = upwardRotation
            }
        }
        
        return fileEntity
    }
}
