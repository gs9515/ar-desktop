//
//  ContentView.swift
//  ar-desktop
//
//  Created by Gary Smith on 2/17/25.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace

    @State var showImmersiveSpace = false

    var body: some View {
        GeometryReader { proxy in
            let textWidth = min(max(proxy.size.width * 0.4, 300), 500)
            ZStack {
                HStack(spacing: 60) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Vision Stack Pro")
                            .font(.system(size: 50, weight: .bold))
                            .padding(.bottom, 15)

                        Text("""
                            To start stacking cubes, click on the 'Start Stacking' button. Point with your left index finger where you want a cube to spawn. Make a pinching gesture with your right hand to drop a cube.

                            You can place the cubes on tables and other surfaces, and also interact with them using your hands!
                            """)
                            .padding(.bottom, 30)
                            .accessibilitySortPriority(3)

                        Toggle(showImmersiveSpace ? "Stop Stacking" : "Start Stacking", isOn: $showImmersiveSpace)
                            .onChange(of: showImmersiveSpace) { _, isShowing in
                                Task {
                                    if isShowing {
                                        await openImmersiveSpace(id: "StackingSpace")
                                    } else {
                                        await dismissImmersiveSpace()
                                    }
                                }
                            }
                            .toggleStyle(.button)
                    }
                    .frame(width: textWidth)
                }
            }
        }
    }
}

            
            
//        VStack {
//            Model3D(named: "Scene", bundle: realityKitContentBundle)
//                .padding(.bottom, 50)
//
//            Text("Hello, world!")
//
////            ToggleImmersiveSpaceButton()
//            Toggle(showImmersiveSpace ? "Stop Stacking" : "Start Stacking", isOn:$showImmersiveSpace)
//                .onChange(of: showImmersiveSpace) { n_, isShowing in
//                    // open immersive space
//                    if isShowing {
//                        await openImmersiveSpace(id: "StackingSpace")
//                    } else{
//                        await dismissImmersiveSpace()
//                    }
//                }
//        }
//        .padding()
//    }
//}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
