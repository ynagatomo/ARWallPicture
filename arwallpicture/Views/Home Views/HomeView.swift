//
//  HomeView.swift
//  arwallpicture
//
//  Created by Yasuhito Nagatomo on 2022/12/13.
//

import SwiftUI
import PhotosUI

struct HomeView: View {
    @ObservedObject var appState: AppState

    @AppStorage(AppConstant.keyARDebugOptionOn) var arDebugOptionOn = false
    @AppStorage(AppConstant.keyPeopleOcclusionOn) var peopleOcclusionOn = false
    @AppStorage(AppConstant.keyObjectOcclusionOn) var objectOcclusionOn = false
    @AppStorage(AppConstant.keySampleImagesOn) var sampleImagesOn = true

    @State private var showingSettings = false
    @State private var showingAR = false

    @State private var selectedItems: [PhotosPickerItem] = []
//    @State private var selectedImages: [UIImage] = []

    private var imageExists: Bool {
        !appState.images.isEmpty
    }

    var body: some View {
        ZStack {
            Color("HomeBGColor")

            VStack {
                if appState.imageState == .idle {
                    ScrollView(showsIndicators: false) {
                        ImageListView(images: appState.images)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                } else {
                    VStack {
                        Spacer()
                        ProgressView()
                            .frame(maxWidth: AppConstant.imageDisplayMaxWidth)
                        Spacer()
                    } // VStack
                } // if
            } // VStack
            .overlay {
                VStack {
                    HStack {
                        Button(action: { showingSettings = true }, label: {
                            Image(systemName: "gear")
                                .foregroundColor(.blue)
                                .font(.title)
                        })
//                        .buttonStyle(.borderedProminent)
                        .padding(.top, 40)

                        Spacer()
                    }

                    Spacer()

                    HStack {
                        PhotosPicker(selection: $selectedItems,
                                     maxSelectionCount: 6,
                                     matching: .images) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.title2)
                        }
                        .onChange(of: selectedItems) { newValues in
                            Task {
                                appState.imageState = .loading
                                var selectedImages: [UIImage] = []
                                for value in newValues {
                                    if let imageData = try? await value.loadTransferable(type: Data.self),
                                       let image = UIImage(data: imageData) {
                                        selectedImages.append(image)
                                    }
                                }
                                appState.setImages(selectedImages)
                                appState.imageState = .idle
                            }
                         }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.imageState != .idle)

                        Spacer()

                        Button(action: displayAR, label: {
                            Label("Display", systemImage: "arkit")
                                .font(.title2)
                        })
                        .buttonStyle(.borderedProminent)
                        .disabled(ProcessInfo.processInfo.isiOSAppOnMac
                                  || !imageExists
                                  || appState.imageState != .idle)

                        Spacer()
                    }
                }
                .padding(24)
            } // .overlay
            .fullScreenCover(isPresented: $showingAR) {
                ARContentView(images: appState.images,
                              arDebugOptionOn: arDebugOptionOn,
                              peopleOcclusionOn: peopleOcclusionOn,
                              objectOcclusionOn: objectOcclusionOn)
            }
            .sheet(isPresented: $showingSettings,
                   onDismiss: {
                if (sampleImagesOn && !imageExists)
                || (!sampleImagesOn && imageExists) {
                    appState.initImages(option: sampleImagesOn)
                }
            },
            content: {
                SettingsView(
                    peopleOcclusionOn: $peopleOcclusionOn,
                    objectOcclusionOn: $objectOcclusionOn,
                    arDebugOptionOn: $arDebugOptionOn,
                    sampleImagesOn: $sampleImagesOn)
                .ignoresSafeArea()
                .presentationDetents([.medium])
            })
        } // ZStack
        .ignoresSafeArea()
        .foregroundColor(.white)
        .onAppear {
            appState.initImages(option: sampleImagesOn)
        }
    }

    private func displayAR() {
        showingAR = true
    }
}

struct HomeView_Previews: PreviewProvider {
    static let appState = AppState()
    static var previews: some View {
        HomeView(appState: appState)
    }
}
