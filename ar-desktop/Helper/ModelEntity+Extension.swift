//
//  ModelEntity+Extension.swift
//  ar-desktop
//
//  Created by Gary Smith on 2/25/25.
//

import RealityKit

extension ModelEntity {
    
    class func createFingertip() -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateSphere (radius: 0.01),
            materials: [UnlitMaterial(color: .cyan)],
            collisionShape: .generateSphere(radius: 0.005),
            mass: 0.0
        )
        
        entity.components.set(PhysicsBodyComponent(mode:.kinematic))
        entity.components.set(OpacityComponent(opacity: 1.0))
        
        return entity
    }
}
