//
//  SettingsView.swift
//  arwallpicture
//
//  Created by Yasuhito Nagatomo on 2022/12/13.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var peopleOcclusionOn: Bool
    @Binding var objectOcclusionOn: Bool
    @Binding var arDebugOptionOn: Bool
    @Binding var sampleImagesOn: Bool

    var body: some View {
        ZStack {
            Color.gray

            VStack {
                HStack {
                    Text("Settings")
                        .font(.title3)
                        .padding(.horizontal, 8)
                    Text(Bundle.main.appName
                         + " v" + Bundle.main.appVersion
                         + " (" + Bundle.main.buildNumber + ")")
                    .font(.caption)

                    Spacer()
                    Button(action: dismiss.callAsFunction, label: {
                        Text("Done")
                    })
                    .font(.title3)
                    .padding(.horizontal, 8)
                }.padding(.top, 16)

                List {
                    #if DEBUG
                    Section(content: {
                        Toggle("AR debug info", isOn: $arDebugOptionOn)
                    },
                    header: { Text("Debug")})
                    #endif

                    Section(content: {
                        Toggle("Sample Images", isOn: $sampleImagesOn)
                    },
                    header: { Text("Sample Images")})

                    Section(content: {
                        Toggle("People Occlusion", isOn: $peopleOcclusionOn)
                            .disabled(!ARViewController.peopleOcclusionSupported)
                        Toggle("Object Occlusion", isOn: $objectOcclusionOn)
                            .disabled(!ARViewController.objectOcclusionSupported)
                    },
                    header: { Text("AR Display")})
                }
                .foregroundColor(.primary)
                .tint(.orange)
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    @State static var peopleOcclusionOn = false
    @State static var objectOcclusionOn = false
    @State static var arDebugOptionOn = false
    @State static var sampleImagesOn = true

    static var previews: some View {
        SettingsView(peopleOcclusionOn: $peopleOcclusionOn,
                     objectOcclusionOn: $objectOcclusionOn,
                     arDebugOptionOn: $arDebugOptionOn,
                     sampleImagesOn: $sampleImagesOn)
    }
}
