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
    @State var immersiveSpaceIsActive = false

    var body: some View {
        GeometryReader { proxy in
            let textWidth = min(max(proxy.size.width * 0.4, 300), 500)
            
            ZStack {
                HStack(spacing: 60) {
                    VStack(alignment: .center, spacing: 0) {  // Ensure center alignment
                        Text("AR Desktop")
                            .font(.system(size: 50, weight: .bold))
                            .padding(.bottom, 15)

                        Text("""
                            To start the desktop environment, click on the 'Start Desktop' button. Point with your left index finger where you want a entity to spawn. Make a pinching gesture with your right hand to drop the entity.

                            You can place the entities on tables and other surfaces, and also interact with them using your hands!
                            """)
                            .multilineTextAlignment(.center)  // Ensures text is centered
                            .padding(.bottom, 30)
                            .accessibilitySortPriority(3)

                        Toggle(showImmersiveSpace ? "Stop Desktop" : "Start Desktop", isOn: $showImmersiveSpace)
                            .onChange(of: showImmersiveSpace) { _, isShowing in
                                Task {
                                    if isShowing {
                                        await openImmersiveSpace(id: "StackingSpace")
                                        immersiveSpaceIsActive = true
                                    } else if immersiveSpaceIsActive {
                                        await dismissImmersiveSpace()
                                        immersiveSpaceIsActive = false
                                    }
                                }
                            }
                            .toggleStyle(.button)
                    }
                    .frame(width: textWidth)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)  // Ensures centering
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)  // Ensures ZStack fills space
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
        .environmentObject(AppModel())
}
