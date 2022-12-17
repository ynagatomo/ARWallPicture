//
//  AssetManager.swift
//  arwallpicture
//
//  Created by Yasuhito Nagatomo on 2022/12/13.
//

import RealityKit

final class AssetManager {
    static let share = AssetManager()

    var modelEntities: [String: ModelEntity] = [:]

    private init() { }

    func loadModelEntity(of name: String) -> ModelEntity? {
//        if modelEntity == nil {
//            let meshRes = MeshResource.generatePlane(width: 0.5, height: 0.5)
//            let material = SimpleMaterial(color: .gray, isMetallic: false)
//            modelEntity = ModelEntity(mesh: meshRes, materials: [material])
//        }

        if let modelEntity = modelEntities[name] {
            return modelEntity
        }

        if let modelEntity = try? ModelEntity.loadModel(named: name) {
            modelEntities[name] = modelEntity
            return modelEntity
        }

        fatalError("Failed to load a model (\(name)).")
    }
}
