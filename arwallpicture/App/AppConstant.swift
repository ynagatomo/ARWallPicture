//
//  AppConstant.swift
//  arwallpicture
//
//  Created by Yasuhito Nagatomo on 2022/12/13.
//

import Foundation

struct AppConstant {
    // Layout
    static let imageDisplayMaxWidth: CGFloat = 600

    // Keys for @AppStorage (saved in UserDefaults)
    static let keyARDebugOptionOn = "keyARDebugOptionOn"
    static let keyPeopleOcclusionOn = "keyPeopleOcclusionOn"
    static let keyObjectOcclusionOn = "keyObjectOcclusionOn"
    static let keySampleImagesOn = "keySampleImagesOn"

    // Sample Image Names in app bundle.
    static let sampleImageNames = [
        // "testh1", "testv1",
        "sample3", "sample2", "sample1",
        "sample6", "sample5", "sample4"
    ]

    // Picture Frame Spec
    struct PictureFrameSpec {
        let modelName: String   // USDZ model name (wo ext)
        let enableVisualEffect: Bool
    }

    // Note: Add or replace picture frame USDZ model as you like
    static let pictureFrameSpecs = [
        PictureFrameSpec(modelName: "panel1",  // USDZ model name
                        enableVisualEffect: false)
    ]

    // AR Render-loop
    static let angleScanIntervalTime: Double = 1.0 // [sec]
}
