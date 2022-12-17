//
//  AppState.swift
//  arwallpicture
//
//  Created by Yasuhito Nagatomo on 2022/12/13.
//

import UIKit

@MainActor
final class AppState: ObservableObject {
    enum ImageState {
        case idle, loading
    }

    @Published var images: [UIImage] = []
    @Published var imageState = ImageState.idle

    func initImages(option enableSample: Bool) {
        if enableSample {
            images = AppConstant.sampleImageNames.compactMap {
                UIImage(named: $0)
            }
        } else {
            images = []
        }
    }

    func setImages(_ images: [UIImage]) {
        self.images = images
    }
}
