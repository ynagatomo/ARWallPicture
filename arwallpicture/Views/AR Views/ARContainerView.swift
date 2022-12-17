//
//  ARContainerView.swift
//  arwallpicture
//
//  Created by Yasuhito Nagatomo on 2022/12/13.
//

import SwiftUI

struct ARContainerView: UIViewControllerRepresentable {
    let images: [UIImage]
    let pictureFrameIndex: Int
    let arDebugOptionOn: Bool
    let peopleOcclusionOn: Bool
    let objectOcclusionOn: Bool

    func makeUIViewController(context: Context) -> ARViewController {
        let arViewController = ARViewController()
        arViewController.setImages(images)
        arViewController.setOptions(arDebugOptionOn: arDebugOptionOn,
                                    peopleOcclusionOn: peopleOcclusionOn,
                                    objectOcclusionOn: objectOcclusionOn)
        return arViewController
    }

    func updateUIViewController(_ uiViewController: ARViewController, context: Context) {
        uiViewController.update(pictureFrameIndex: pictureFrameIndex)
    }
}

//    struct ARContainerView_Previews: PreviewProvider {
//        static var previews: some View {
//            ARContainerView()
//        }
//    }
