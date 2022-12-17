//
//  ARViewController.swift
//  arwallpicture
//
//  Created by Yasuhito Nagatomo on 2022/12/13.
//

import UIKit
import ARKit
import RealityKit
import Combine

// swiftlint:disable file_length

final class ARViewController: UIViewController {
    struct DetectedPlane {
        let identifier: UUID // id of ARPlaneAnchor
        var translation: SIMD3<Float>
        var rotation: simd_quatf
        var isVertical: Bool
        var width: Float
        var height: Float
        let planeEntity: ModelEntity // guide plane

        var isEnable: Bool {
            width >= 0.5 && height >= 0.5 // [meters]
        }
    }

    private var detectedPlanes: [DetectedPlane] = []
    private var displayingPlaneSize: (width: Float, height: Float) = (0, 0)

    private var pictureFrameModelEntity: ModelEntity?
    private var pictureFrameTextures: [PhysicallyBasedMaterial.Texture] = []
    private var pictureFrameTextureSizes: [CGSize] = []
    private var displayingTextureIndex = 0

    enum DisplayState {
        case idle, detectingPlanes, displayingPictures
    }

    private var arView: ARView!
    private var arSessionConfig: ARWorldTrackingConfiguration!
    private var baseAnchor: AnchorEntity!
    private var detectPlanesEntity: Entity!
    private var displayState: DisplayState = .idle

#if !targetEnvironment(simulator)
    var coachingOverlayView: ARCoachingOverlayView!
#endif

    private var replaceButton: UIButton!
    private var activateButton: UIButton!

    private var renderLoopSubscription: Cancellable?
    private var cumulativeTimeForTexture: Double = 0
    private var isGeometryModifierEnabled = false
    private var usingGeometryModifier = false
    private var geometryModifier: CustomMaterial.GeometryModifier!

    private var pictureFrameIndex = 0
    private var arDebugOptionOn = false
    private var peopleOcclusionOn = false
    private var objectOcclusionOn = false
    private var intervalTime: Double = 1.0

    static var peopleOcclusionSupported: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth)
    }
    static var objectOcclusionSupported: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

#if !targetEnvironment(simulator)
        // running on a real device
        arView = ARView(frame: .zero,
                        cameraMode: .ar,
                        automaticallyConfigureSession: true)
#else
        // running on a simulator
        arView = ARView(frame: .zero)
#endif

        view = arView
        baseAnchor = AnchorEntity()
        arView.scene.addAnchor(baseAnchor)
        prepareCustomMaterial()

#if DEBUG
        if arDebugOptionOn {
            arView.debugOptions = [ // .showAnchorOrigins,
                // .showPhysics : collision shapes
                .showStatistics,
                .showWorldOrigin
                // .showAnchorGeometry,
                // .showFeaturePoints
            ]
        }
#endif

        // create a coachingOverlayView
#if !targetEnvironment(simulator)
        coachingOverlayView = ARCoachingOverlayView()   // class : UIView
        coachingOverlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(coachingOverlayView)

        // coachingOverlayView.goal = .tracking // a goal for the basic world tracking
        coachingOverlayView.goal = .anyPlane
        coachingOverlayView.activatesAutomatically = false
        coachingOverlayView.session = arView.session
        coachingOverlayView.delegate = self
        coachingOverlayView.setActive(false, animated: false)
#endif

        // Tap Gesture
        let tap = UITapGestureRecognizer(target: self,
                                         action: #selector(self.tapHandler(_:)))
        view.addGestureRecognizer(tap)

        // Replace Button
        setupReplaceButton()
        view.addSubview(replaceButton)

        // Activate Button
        setupActivateButton()
        view.addSubview(activateButton)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        arView.session.delegate = self

        startPlaneDetection()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        deactivateCoaching()
        stopEventLoop()
        arView.session.pause()
    }

    @objc func tapHandler(_ sender: UITapGestureRecognizer? = nil) {
        guard displayState == .detectingPlanes else { return }
        guard let touchInView = sender?.location(in: view) else { return }
        if let tappedEntity = arView.entity(at: touchInView) {
            //            debugLog("DEBUG: 🔥 tapped entity = \(tappedEntity)")
            startDisplayingPictures(on: tappedEntity)
        }
    }

    private func setupReplaceButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 28)
        let image = UIImage(systemName: "rectangle.and.hand.point.up.left.fill",
                            withConfiguration: config)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        replaceButton = UIButton()
        replaceButton.frame = CGRect(x: CGFloat(38), y: CGFloat(64),
                                     width: CGFloat(64), height: CGFloat(64))
        replaceButton.setImage(image, for: .normal)
        replaceButton.addTarget(self,
                                action: #selector(self.replaceButtonTapped(sender:)),
                                for: .touchUpInside)
        replaceButton.isEnabled = false
    }

    @objc func replaceButtonTapped(sender: UIButton) {
        startPlaneDetection()
    }

    private func setupActivateButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 28)
        let image = UIImage(systemName: "wand.and.stars.inverse", // party.popper.fill
                            withConfiguration: config)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        activateButton = UIButton()
        activateButton.frame = CGRect(x: CGFloat(110), y: CGFloat(64),
                              width: CGFloat(64), height: CGFloat(64))
        activateButton.setImage(image, for: .normal)
        activateButton.addTarget(self,
                         action: #selector(self.activateButtonTapped(sender:)),
                         for: .touchUpInside)
        activateButton.isEnabled = false
    }

    @objc func activateButtonTapped(sender: UIButton) {
        isGeometryModifierEnabled.toggle()
        cumulativeTimeForTexture = 0 // force refresh
    }
}

// MARK: - Setup

extension ARViewController {
    func setImages(_ images: [UIImage]) {
        // create all texture images
        images.forEach {
            if let cgImage = $0.cgImage {
                let options = TextureResource.CreateOptions(semantic: .color)
                if let textureRes = try? TextureResource.generate(from: cgImage,
                                                                  options: options) {
                    let texture = PhysicallyBasedMaterial.Texture(textureRes)
                    pictureFrameTextures.append(texture) // image
                    pictureFrameTextureSizes.append($0.size) // size
                }
            }
        }
    }

    func setOptions(arDebugOptionOn: Bool, peopleOcclusionOn: Bool, objectOcclusionOn: Bool) {
        self.arDebugOptionOn = arDebugOptionOn
        self.peopleOcclusionOn = peopleOcclusionOn
        self.objectOcclusionOn = objectOcclusionOn
    }
}

// MARK: - Update

extension ARViewController {
    func update(pictureFrameIndex: Int) {
        assert(pictureFrameIndex >= 0
               && pictureFrameIndex < AppConstant.pictureFrameSpecs.count)

        self.pictureFrameIndex = pictureFrameIndex
        pictureFrameModelEntity = loadPictureFrameModel(of: pictureFrameIndex)
        pictureFrameModelEntity?.name = "picture"
    }

    private func loadPictureFrameModel(of frameIndex: Int) -> ModelEntity? {
        assert(pictureFrameIndex >= 0
               && pictureFrameIndex < AppConstant.pictureFrameSpecs.count)

         return AssetManager.share.loadModelEntity(of:
                                       AppConstant.pictureFrameSpecs[frameIndex].modelName)
    }
}

// MARK: - Display Pictures

extension ARViewController {
    private func startPlaneDetection() {
        displayState = .detectingPlanes
        replaceButton.isEnabled = false
        activateButton.isEnabled = false

        // remove a picture if exists
        if let entity = baseAnchor.findEntity(named: "picture") {
            baseAnchor.removeChild(entity)
        }

        detectPlanesEntity = Entity()
        baseAnchor.addChild(detectPlanesEntity)
        removeAllDetectedPlane() // init

        activateCoaching()
        startPlaneDetectionARSession()
    }

    private func startDisplayingPictures(on entity: Entity) {
        if let plane = findDetectedPlane(of: entity) {
            displayState = .displayingPictures
            replaceButton.isEnabled = true
            activateButton.isEnabled = true

            // stop displaying guide planes
            baseAnchor.removeChild(detectPlanesEntity) // remove plane entities
            detectPlanesEntity = nil
            removeAllDetectedPlane()    // remove plane data

            // place one frame on the selected plane
            addPictureEntity(on: plane)
            displayingPlaneSize = (width: plane.width,
                                   height: plane.height)

            // change AR session to non-plane detection
            startNonPlaneDetectionARSession()

            startEventLoop()
        } else {
            debugLog("AR: Failed to find the detected plane.")
        }
    }

    private func calcScale(planeWidth: Float, planeHeight: Float) -> (scaleX: Float, scaleZ: Float) {
        let scaleH = planeWidth
               / Float(pictureFrameTextureSizes[displayingTextureIndex].width)
        let scaleV = planeHeight
               / Float(pictureFrameTextureSizes[displayingTextureIndex].height)
        let scaleCommon = min(scaleH, scaleV)
        let scaleX = scaleCommon * Float(pictureFrameTextureSizes[displayingTextureIndex].width)
        let scaleZ = scaleCommon * Float(pictureFrameTextureSizes[displayingTextureIndex].height)

        return (scaleX, scaleZ)
    }

    private func addPictureEntity(on plane: DetectedPlane) {
        guard let model = pictureFrameModelEntity else { return }

        displayingTextureIndex = 0
        if !pictureFrameTextures.isEmpty {
            var material = UnlitMaterial()
            material.color.texture = pictureFrameTextures[displayingTextureIndex]
            model.model?.materials[0] = material
        }

        let (scaleX, scaleZ) = calcScale(planeWidth: plane.width,
                                         planeHeight: plane.height)

        model.scale = SIMD3<Float>(scaleX, 1.0, scaleZ)
        model.transform.rotation = plane.rotation
        model.transform.translation = plane.translation

        baseAnchor.addChild(model)

//            if let pictureFrameModelEntity {
//                if !pictureFrameTextures.isEmpty {
//                    var material = UnlitMaterial()
//                    material.color.texture = pictureFrameTextures[displayingTextureIndex]
//                    pictureFrameModelEntity.model?.materials[0] = material
//                }
//
//                anchorEntity.addChild(pictureFrameModelEntity)
//                pictureFrameModelEntity.orientation = simd_quatf(angle: Float.pi / 2,
//                                                                 axis: SIMD3<Float>(1, 0, 0))
//                * simd_quatf(angle: Float.pi, axis: SIMD3<Float>(0, 1, 0))
//                * simd_quatf(angle: Float.pi, axis: SIMD3<Float>(0, 0, 1))
//
//                let scale = min(planeAnchor.width, planeAnchor.height)
//                pictureFrameModelEntity.scale = SIMD3<Float>(scale, scale, 1)
//    //            pictureFrameModelEntity.scale = SIMD3<Float>(1, 1, 1)
//
//                pictureFrameModelEntity.transform.translation =
//                SIMD3<Float>(planeAnchor.center.x,
//                             planeAnchor.center.z,
//                             0)
//            }
    }

//    private func updatePictureEntity() {
//        guard let pictureFrameModelEntity else { return }
//
//        let scale = min(planeAnchor.width, planeAnchor.height)
//        pictureFrameModelEntity.scale = SIMD3<Float>(scale, scale, scale)
//    }

    private func prepareCustomMaterial() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Failed to create the default metal device.")
        }

        let library = device.makeDefaultLibrary()!
        geometryModifier = CustomMaterial.GeometryModifier(
                named: "pictureGeometryModifier", in: library)
    }
}

// MARK: - Render Loop

extension ARViewController {
    private func stopEventLoop() {
        renderLoopSubscription = nil
    }

    private func startEventLoop() {
        cumulativeTimeForTexture = 0

        renderLoopSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { event in
            DispatchQueue.main.async {
                self.updateScene(deltaTime: event.deltaTime)
            }
        }
    }

    // swiftlint:disable function_body_length
    private func updateScene(deltaTime: Double) {
        guard let pictureFrameModelEntity else { return }

        cumulativeTimeForTexture += deltaTime

        // change the texture

        guard pictureFrameTextures.count >= 2 else { return }

        if cumulativeTimeForTexture > intervalTime {
            cumulativeTimeForTexture = 0

            let camPos = arView.cameraTransform.translation
            let picPos = pictureFrameModelEntity.transform.translation
            let picToCam = camPos - picPos
            let rotation = pictureFrameModelEntity.transform.rotation
            let inverse = simd_inverse(rotation)
            let invVec = simd_act(inverse, simd_float3(picToCam))
            let cosTheta = (0 * invVec.x + 1 * invVec.y)
                        / sqrtf(invVec.x * invVec.x + invVec.y * invVec.y)
            let theta = acosf(cosTheta) * sign(invVec.x)  // -pi/2...pi/2
            // let degrees = toDegreesFrom(radians: theta)

            var index = Int((theta + Float.pi / 2)
                            / (Float.pi / Float(pictureFrameTextures.count)))
            if index < 0 { index = 0 }
            if index >= pictureFrameTextures.count {
                index = pictureFrameTextures.count - 1
            }

            if index != displayingTextureIndex
                || isGeometryModifierEnabled != usingGeometryModifier {
                displayingTextureIndex = index

                var material = UnlitMaterial()
                material.color.texture = pictureFrameTextures[index]

                if isGeometryModifierEnabled {
                    if let customMaterial = try?
                        CustomMaterial(from: material,
                                       geometryModifier: geometryModifier) {
                        pictureFrameModelEntity.model?.materials[0] = customMaterial
                        usingGeometryModifier = true
                    } else {
                        debugLog("AR: failed to create the custom shader.")
                        pictureFrameModelEntity.model?.materials[0] = material
                        usingGeometryModifier = false
                    }
                } else {
                    pictureFrameModelEntity.model?.materials[0] = material
                    usingGeometryModifier = false
                }

                let (scaleX, scaleZ) = calcScale(
                    planeWidth: displayingPlaneSize.width,
                    planeHeight: displayingPlaneSize.height)
                pictureFrameModelEntity.scale = SIMD3<Float>(scaleX, 1.0, scaleZ)
            }
        }
    }
}

// MARK: - ARSession

extension ARViewController {
    private func activateCoaching() {
        #if !targetEnvironment(simulator)
        coachingOverlayView.activatesAutomatically = true   // when false, coaching will not finish
        coachingOverlayView.setActive(true, animated: false)
        #endif
    }

    private func deactivateCoaching() {
        #if !targetEnvironment(simulator)
        if coachingOverlayView.isActive {
            coachingOverlayView.setActive(false, animated: false)
        }
        #endif
    }

    private func startPlaneDetectionARSession() {
        #if !targetEnvironment(simulator)
        // running on an real devices
        if arSessionConfig == nil {
            arSessionConfig = ARWorldTrackingConfiguration()

            if peopleOcclusionOn {
                if Self.peopleOcclusionSupported {
                    arSessionConfig.frameSemantics.insert(.personSegmentationWithDepth)
                    debugLog("AR: People Occlusion was enabled.")
                } else {
                    debugLog("AR: This device does not support People Occlusion.")
                }
            }

            // [Note]
            // When you enable scene reconstruction, ARKit provides a polygonal mesh
            // that estimates the shape of the physical environment.
            // If you enable plane detection, ARKit applies that information to the mesh.
            // Where the LiDAR scanner may produce a slightly uneven mesh on a real-world surface,
            // ARKit smooths out the mesh where it detects a plane on that surface.
            // If you enable people occlusion, ARKit adjusts the mesh according to any people
            // it detects in the camera feed. ARKit removes any part of the scene mesh that
            // overlaps with people
            if objectOcclusionOn {
                if Self.objectOcclusionSupported {
                    arSessionConfig.sceneReconstruction = .mesh
                    arView.environment.sceneUnderstanding.options.insert(.occlusion)
                    debugLog("AR: Object Occlusion was enabled.")
                } else {
                    debugLog("AR: This device does not support Object Occlusion.")
                }
            }
        }
        arSessionConfig.planeDetection = [.horizontal, .vertical]
        arView.session.run(arSessionConfig, options: [.resetTracking,
                                                      .resetSceneReconstruction,
                                                      .removeExistingAnchors])
        #else
        // running on a simulator => do nothing
        #endif
    }

    private func startNonPlaneDetectionARSession() {
        assert(arSessionConfig != nil)
        #if !targetEnvironment(simulator)
        // running on an real devices
        arSessionConfig.planeDetection = []
        arView.session.run(arSessionConfig, options: [.removeExistingAnchors])
        #else
        // running on a simulator => do nothing
        #endif
    }
}

// MARK: - ARCoachingDelegate

extension ARViewController: ARCoachingOverlayViewDelegate {
    func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
        debugLog("AR: AR-COACHING: The AR coaching overlay will activate.")
    }

    func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
        debugLog("AR: AR-COACHING: The AR coaching overlay did deactivate.")

//        DispatchQueue.main.async {
//            self.arScene.setupScene()
//            self.arScene.startShowing()
//        }
    }
}

// MARK: - ARSessionDelegate

extension ARViewController: ARSessionDelegate {
    private func makeDetectedPlane(of anchor: ARPlaneAnchor, entity: ModelEntity)
    -> DetectedPlane {
        return DetectedPlane(identifier: anchor.identifier,
                             translation: SIMD3<Float>(anchor.transform[3].x,
                                                       anchor.transform[3].y,
                                                       anchor.transform[3].z)
                                        + anchor.center,
                             rotation: simd_quatf(anchor.transform)
                                       * simd_quatf(angle: anchor.planeExtent.rotationOnYAxis,
                                         axis: SIMD3<Float>(0, 1, 0)),
                             isVertical: anchor.alignment == .vertical,
                             width: anchor.planeExtent.width,
                             height: anchor.planeExtent.height,
                             planeEntity: entity)
    }

    private func updateDetectedPlanes(with plane: DetectedPlane) {
        if let index = detectedPlanes.firstIndex(where: {
            $0.identifier == plane.identifier}) {
            detectedPlanes[index] = plane // updated
        } else {
            assertionFailure("failed to find the detected plane.")
        }
    }

    private func removeDetectedPlane(of plane: ARPlaneAnchor) {
        guard !detectedPlanes.isEmpty else { return }

        let preCount = detectedPlanes.count
        detectedPlanes.removeAll(where: { $0.identifier == plane.identifier })

        assert(preCount == detectedPlanes.count + 1)
    }

    private func removeAllDetectedPlane() {
        detectedPlanes = []
    }

    private func findDetectedPlane(of entity: Entity) -> DetectedPlane? {
        return detectedPlanes.first(where: {
            $0.planeEntity.id == entity.id
        })
    }

    private func generateGuideModel(color: UIColor? = nil) -> ModelEntity {
        let uiColor = color != nil ? color!
                                : UIColor(red: CGFloat.random(in: 0.5...1.0),
                                          green: CGFloat.random(in: 0.5...1.0),
                                          blue: CGFloat.random(in: 0.5...1.0),
                                          alpha: 0.8)

        var material = SimpleMaterial()
        material.color.tint = uiColor
        let meshResource = MeshResource.generatePlane(
            width: 1.0, depth: 1.0) // normalized size
        let model = ModelEntity(mesh: meshResource, materials: [material])
        model.generateCollisionShapes(recursive: false)
        return model
    }

    /// tells that ARAnchors was added cause of like a plane-detection
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        // <AREnvironmentProbeAnchor> can be added for environmentTexturing
        guard displayState == .detectingPlanes else { return }

        for anchor in anchors {
            if let arPlaneAnchor = anchor as? ARPlaneAnchor {
                // debugLog("AR: DELEGATE: didAdd an ARPlaneAnchor: \(arPlaneAnchor)")

                let model = generateGuideModel() // X-Z plane
                let detectedPlane = makeDetectedPlane(of: arPlaneAnchor, entity: model)

                model.scale = SIMD3<Float>(detectedPlane.width, 1.0,
                                                detectedPlane.height)
                model.transform.rotation = detectedPlane.rotation
                model.transform.translation = detectedPlane.translation

                model.isEnabled = detectedPlane.isEnable
//                baseAnchor.addChild(model)
                detectPlanesEntity.addChild(model)
                detectedPlanes.append(detectedPlane)
            }
        }
    }

    /// tells that ARAnchors were changed cause of like a progress of plane-detection
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard displayState == .detectingPlanes else { return }

        for anchor in anchors {
            if let arPlaneAnchor = anchor as? ARPlaneAnchor {
                // debugLog("AR: DELEGATE: didUpdate an ARPlaneAnchor: \(arPlaneAnchor)")

                if let detectedPlane = detectedPlanes.first(where: {
                    $0.identifier == arPlaneAnchor.identifier
                }) {
                    let updatedPlane = makeDetectedPlane(of: arPlaneAnchor,
                                                         entity: detectedPlane.planeEntity)
                    updateDetectedPlanes(with: updatedPlane)
                    let model = updatedPlane.planeEntity

                    model.isEnabled = updatedPlane.isEnable
                    if updatedPlane.isEnable {
                        model.scale = SIMD3<Float>(detectedPlane.width, 1.0,
                                                        detectedPlane.height)
                        model.transform.rotation = detectedPlane.rotation
                        model.transform.translation = detectedPlane.translation
                    }
                } else {
                    assertionFailure("AR: DELEGATE: failed to fine the DetectedPlane.")
                }
            }
        }
    }

    /// tells that the ARAnchors were removed
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        guard displayState == .detectingPlanes else { return }
        // ARPlaneAnchor can be removed.

        for anchor in anchors {
            if let arPlaneAnchor = anchor as? ARPlaneAnchor {
                removeDetectedPlane(of: arPlaneAnchor)
            }
        }
    }

    //    /// tells that the AR session was interrupted due to app switching or something
    //    func sessionWasInterrupted(_ session: ARSession) {
    //        debugLog("AR: AR-DELEGATE: The sessionWasInterrupted(_:) was called.")
    //        // Nothing to do. The system handles all.
    //
    //        // DispatchQueue.main.async {
    //        //   - do something if necessary
    //        // }
    //    }

    //    /// tells that the interruption was ended
    //    func sessionInterruptionEnded(_ session: ARSession) {
    //        debugLog("AR: AR-DELEGATE: The sessionInterruptionEnded(_:) was called.")
    //        // Nothing to do. The system handles all.
    //
    //        // DispatchQueue.main.async {
    //        //   - reset the AR tracking
    //        //   - do something if necessary
    //        // }
    //    }

    //    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
    // swiftlint:disable line_length
    //        debugLog("AR: AR-DELEGATE: The session(_:cameraDidChangeTrackingState:) was called. cameraState = \(camera.trackingState)")
    //    }

    //    func session(_ session: ARSession, didUpdate frame: ARFrame) {
    //        // You can get the camera's (device's) position in the virtual space
    //        // from the transform property.
    //        // The 4th column represents the position, (x, y, z, -).
    //        let cameraTransform = frame.camera.transform
    //        // The orientation of the camera, expressed as roll, pitch, and yaw values.
    //        let cameraEulerAngles = frame.camera.eulerAngles // simd_float3
    //    }

    // tells that an error was occurred
    //
    // - When the users don't allow to access the camera, this delegate will be called.
    // swiftlint:disable cyclomatic_complexity
    func session(_ session: ARSession, didFailWithError error: Error) {
        debugLog("AR: AR-DELEGATE: The didFailWithError was called.")
        debugLog("AR: AR-DELEGATE:     error = \(error.localizedDescription)")
        guard let arerror = error as? ARError else { return }

        #if DEBUG
        // print the errorCase
        let errorCase: String
        switch arerror.errorCode {
        case ARError.Code.requestFailed.rawValue: errorCase = "requestFailed"
        case ARError.Code.cameraUnauthorized.rawValue: errorCase = "cameraUnauthorized"
        case ARError.Code.fileIOFailed.rawValue: errorCase = "fileIOFailed"
        case ARError.Code.insufficientFeatures.rawValue: errorCase = "insufficientFeatures"
        case ARError.Code.invalidConfiguration.rawValue: errorCase = "invalidConfiguration"
        case ARError.Code.invalidReferenceImage.rawValue: errorCase = "invalidReferenceImage"
        case ARError.Code.invalidReferenceObject.rawValue: errorCase = "invalidReferenceObject"
        case ARError.Code.invalidWorldMap.rawValue: errorCase = "invalidWorldMap"
        case ARError.Code.microphoneUnauthorized.rawValue: errorCase = "microphoneUnauthorized"
        case ARError.Code.objectMergeFailed.rawValue: errorCase = "objectMergeFailed"
        case ARError.Code.sensorFailed.rawValue: errorCase = "sensorFailed"
        case ARError.Code.sensorUnavailable.rawValue: errorCase = "sensorUnavailable"
        case ARError.Code.unsupportedConfiguration.rawValue: errorCase = "unsupportedConfiguration"
        case ARError.Code.worldTrackingFailed.rawValue: errorCase = "worldTrackingFailed"
        case ARError.Code.geoTrackingFailed.rawValue: errorCase = "geoTrackingFailed"
        case ARError.Code.geoTrackingNotAvailableAtLocation.rawValue: errorCase = "geoTrackingNotAvailableAtLocation"
        case ARError.Code.locationUnauthorized.rawValue: errorCase = "locationUnauthorized"
        case ARError.Code.invalidCollaborationData.rawValue: errorCase = "invalidCollaborationData"
        default: errorCase = "unknown"
        }
        debugLog("AR: AR-DELEGATE:     errorCase = \(errorCase)")

        // print the errorWithInfo
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        // remove optional error messages and connect into one string
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        debugLog("AR: AR-DELEGATE:     errorWithInfo: \(errorMessage)")
        #endif

        // handle the issues
        if arerror.errorCode == ARError.Code.cameraUnauthorized.rawValue {
            // Error: The camera access is not allowed.
            debugLog("AR: AR-DELEGATE:     The camera access is not authorized.")

            // Show the alert message.
            // "The use of the camera is not permitted.\nPlease allow it with the Settings app."
        } else if arerror.errorCode == ARError.Code.unsupportedConfiguration.rawValue {
            // Error: Unsupported Configuration
            // It means that now the AR session is trying to run on macOS(w/M1) or Simulator.
            debugLog("AR: AR-DELEGATE:     unsupportedConfiguration. (running on macOS or Simulator)")
            assertionFailure("invalid ARSession on macOS or Simulator.")
            // Nothing to do in release mode.
        } else {
            // Error: Something else
            // Nothing to do.
        }
    }
}
