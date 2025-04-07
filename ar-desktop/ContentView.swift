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
            let textWidth = min(max(proxy.size.width * 0.4, 500), 500)
            
            ZStack {
                HStack(spacing: 60) {
                    VStack(alignment: .center, spacing: 0) {  // Ensure center alignment
                        Image("AR_Desk")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 100)
                            .padding(.top, 10)
                            .padding(.bottom, 25)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                Text("•")
                                Text("Place your left index finger where you’d like to center your desktop. Then, pinch the “Start Desktop” button below to launch it.")
                            }
                            HStack(alignment: .top) {
                                Text("•")
                                Text("Once your desktop is active, pinch with your right hand to drop groups of files beneath your left finger.")
                            }
                            HStack(alignment: .top) {
                                Text("•")
                                Text("Place these groups on tables or other surfaces. Try pinching a group to open it, or move it around by either pinching and dragging or gently nudging it with your hands.")
                            }
                        }.foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 30)
                        .accessibilitySortPriority(3)
                        
                        Image("little-auras")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 60) // Adjust the height as needed
                            .padding(.bottom, 40)

                        Toggle(showImmersiveSpace ? "Stop Desktop" : "Start Desktop", isOn: $showImmersiveSpace)
//                            .bold()
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
                            .foregroundColor(.black)
                            .tint(Color(red: 1.0, green: 190/255, blue: 0))
                    }
                    .frame(width: textWidth)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)  // Ensures centering
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)  // Ensures ZStack fills space
            .background(Color(red: 1.0, green: 247/255, blue: 232/255)).opacity(0.7)
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
