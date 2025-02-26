//
//  SampleModel.swift
//  ar-desktop
//
//  Created by Gary Smith on 2/25/25.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct SampleModel: View {

    var orientation: SIMD3<Double> = .zero

    var body: some View {
        Model3D(named: "Cube", bundle: realityKitContentBundle) { model in
            model
                .resizable()
                .scaledToFit()
                .rotation3DEffect(
                    Rotation3D(
                        eulerAngles: .init(angles: orientation, order: .xyz)
                    )
                )
        } placeholder: {
            ProgressView().offset(z: 150)
        }
    }
}
