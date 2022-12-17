//
//  ARContentView.swift
//  arwallpicture
//
//  Created by Yasuhito Nagatomo on 2022/12/13.
//

import SwiftUI

struct ARContentView: View {
    @Environment(\.dismiss) private var dismiss

    let images: [UIImage]
    let arDebugOptionOn: Bool
    let peopleOcclusionOn: Bool
    let objectOcclusionOn: Bool

    var body: some View {
        ARContainerView(images: images,
                        pictureFrameIndex: 0,
                        arDebugOptionOn: arDebugOptionOn,
                        peopleOcclusionOn: peopleOcclusionOn,
                        objectOcclusionOn: objectOcclusionOn)
            .ignoresSafeArea()
            .overlay {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: dismiss.callAsFunction) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 44))
                        }
                    }
                    .padding()
                    Spacer()
                }
            }
    }
}

struct ARContentView_Previews: PreviewProvider {
    static var previews: some View {
        ARContentView(images: [],
                      arDebugOptionOn: false,
                      peopleOcclusionOn: false,
                      objectOcclusionOn: false)
    }
}
