//
//  ContentView.swift
//  Crosswire
//
//  This file is part of Crosswire.
//
//  Crosswire is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Crosswire is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Crosswire.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI
import AppKit
import CrosswireKit
import SemanticVersion
import Sparkle

struct ContentView: View {
    @AppStorage("checkEngineUpdates") var checkEngineUpdates = true
    @EnvironmentObject var bottleVM: BottleVM
    @Binding var showSetup: Bool
    let updater: SPUUpdater

    @State var bottlesLoaded: Bool = false
    @State var searchText: String = ""
    @State var openedFileURL: URL?
    @State var setupStartingStage: SetupStage?

    @State var settingsBottle: Bottle?
    @State var provisioningMessage: String?

    init(showSetup: Binding<Bool>, updater: SPUUpdater) {
        self._showSetup = showSetup
        self.updater = updater
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            actionRow
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $settingsBottle) { bottle in
            AppSettingsSheet(bottle: bottle, onDelete: {
                settingsBottle = nil
            })
        }
        .sheet(item: $openedFileURL) { url in
            FileOpenView(fileURL: url,
                         currentBottle: nil,
                         bottles: bottleVM.bottles)
        }
        .sheet(isPresented: $showSetup, onDismiss: { setupStartingStage = nil }, content: {
            SetupView(startingStage: setupStartingStage, showSetup: $showSetup, firstTime: false)
        })
        .overlay {
            if let message = provisioningMessage {
                ProvisioningOverlay(message: message)
            }
        }
        .handlesExternalEvents(preferring: [], allowing: ["*"])
        .onOpenURL { url in
            openedFileURL = url
        }
        .task {
            await onAppearTask()
        }
    }

    // MARK: - Header & action row

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Crosswire")
                .font(.system(size: 22, weight: .semibold))
            Spacer()
            Text(versionString)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(action: installWindowsApp) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Install Windows App")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            TextField("Search apps...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if !bottlesLoaded {
            loadingState
        } else if bottleVM.bottles.isEmpty {
            emptyState
        } else if filteredBottles.isEmpty {
            noMatchState
        } else {
            list
        }
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var noMatchState: some View {
        VStack {
            Spacer()
            Text("No apps match \"\(searchText)\"")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredBottles) { bottle in
                    AppRow(
                        bottle: bottle,
                        onPrimaryAction: { settingsBottle = bottle },
                        onRun: { runPrimary(for: bottle) },
                        onRunSpecific: { program in
                            run(program: program, bottle: bottle)
                        },
                        onOpenSettings: { settingsBottle = bottle }
                    )
                    Divider().padding(.leading, 72)
                }
            }
        }
        .animation(.default, value: bottleVM.bottles)
        .animation(.default, value: searchText)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Drop a Windows .exe to get started")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Button(action: installWindowsApp) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Install Windows App")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Derived

    var filteredBottles: [Bottle] {
        let sorted = bottleVM.bottles.sorted()
        if searchText.isEmpty { return sorted }
        return sorted.filter {
            $0.settings.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        return "v\(short)"
    }

    // MARK: - Lifecycle

    @MainActor
    private func onAppearTask() async {
        bottleVM.loadBottles()
        bottlesLoaded = true

        if !CrosswireEngine.isEnginePresent() {
            setupStartingStage = nil
            showSetup = true
            return
        }

        let updateInfo = await CrosswireEngine.shouldUpdateEngine()
        guard checkEngineUpdates, updateInfo.0 else { return }

        let alert = NSAlert()
        alert.messageText = String(localized: "update.engine.title")
        alert.informativeText = String(format: String(localized: "update.engine.description"),
                                       String(CrosswireEngine.engineVersion()
                                              ?? SemanticVersion(0, 0, 0)),
                                       String(updateInfo.1))
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "update.engine.update"))
        alert.addButton(withTitle: String(localized: "button.removeAlert.cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            CrosswireEngine.uninstall()
            setupStartingStage = .engineSetup
            showSetup = true
        }
    }
}

/// Modal overlay shown while a new app is being provisioned.
struct ProvisioningOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text(message)
                    .font(.system(size: 13))
            }
            .padding(24)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

#Preview {
    ContentView(
        showSetup: .constant(false),
        updater: SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        ).updater
    )
    .environmentObject(BottleVM.shared)
}
