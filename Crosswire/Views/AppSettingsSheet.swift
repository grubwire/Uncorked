//
//  AppSettingsSheet.swift
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
import UniformTypeIdentifiers
import CrosswireKit

/// Per-app settings sheet. Replaces the old BottleView/ProgramsView/
/// WinetricksView flow from the main window. Surfaces just the controls a
/// user needs to manage one installed app.
struct AppSettingsSheet: View {
    @ObservedObject var bottle: Bottle
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var primarySelection: URL?

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                programsSection
                advancedSection
                dangerSection
            }
            .formStyle(.grouped)
            .navigationTitle(bottle.settings.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 540)
        .onAppear {
            primarySelection = bottle.settings.primaryProgramURL
            if bottle.programs.isEmpty {
                bottle.updateInstalledPrograms()
            }
        }
    }

    private var generalSection: some View {
        Section("General") {
            LabeledContent("Installed at") {
                Text(bottle.url.prettyPath())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Picker("Windows version", selection: $bottle.settings.windowsVersion) {
                ForEach(WinVersion.allCases.reversed(), id: \.self) {
                    Text($0.pretty()).tag($0)
                }
            }
            Toggle("DXVK (DirectX to Vulkan)", isOn: $bottle.settings.dxvk)
        }
    }

    @ViewBuilder
    private var programsSection: some View {
        Section("Programs") {
            if bottle.programs.isEmpty {
                Text("No installed programs detected yet.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Primary launcher", selection: $primarySelection) {
                    Text("None").tag(URL?.none)
                    ForEach(bottle.programs) { program in
                        Text(program.name.replacingOccurrences(of: ".exe", with: ""))
                            .tag(Optional(program.url))
                    }
                }
                .onChange(of: primarySelection) { _, newValue in
                    bottle.settings.primaryProgramURL = newValue
                }
                ForEach(bottle.programs) { program in
                    HStack {
                        Text(program.name.replacingOccurrences(of: ".exe", with: ""))
                        Spacer()
                        Button("Run") { runProgram(program) }
                    }
                }
            }
            Button("Rescan installed programs") {
                bottle.updateInstalledPrograms()
            }
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            Button("Open in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([bottle.url])
            }
            Button("Open Terminal") {
                bottle.openTerminal()
            }
            Button("Run a .exe inside this app...") {
                pickAdHocExecutable()
            }
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                confirmDelete()
            } label: {
                Text("Delete app").foregroundStyle(.red)
            }
        } header: {
            Text("Danger")
        }
    }

    private func runProgram(_ program: Program) {
        NSApp.miniaturizeAll(nil)
        Task(priority: .userInitiated) {
            do {
                try await Wine.runProgram(at: program.url, bottle: bottle)
            } catch {
                print("Failed to run program: \(error)")
            }
        }
    }

    private func pickAdHocExecutable() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType.exe,
            UTType(exportedAs: "com.microsoft.msi-installer"),
            UTType(exportedAs: "com.microsoft.bat")
        ]
        panel.directoryURL = bottle.url.appending(path: "drive_c")
        panel.begin { result in
            guard result == .OK, let url = panel.urls.first else { return }
            Task { @MainActor in
                NSApp.miniaturizeAll(nil)
                do {
                    if url.pathExtension == "bat" {
                        try await Wine.runBatchFile(url: url, bottle: bottle)
                    } else {
                        try await Wine.runProgram(at: url, bottle: bottle)
                    }
                } catch {
                    print("Failed to run ad-hoc program: \(error)")
                }
                bottle.updateInstalledPrograms()
            }
        }
    }

    private func confirmDelete() {
        let alert = NSAlert()
        alert.messageText = "Delete \(bottle.settings.name)?"
        alert.informativeText = "This removes the app's files and cannot be undone."
        alert.alertStyle = .warning
        let delete = alert.addButton(withTitle: "Delete")
        delete.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task(priority: .userInitiated) { @MainActor in
            try? FileManager.default.removeItem(at: bottle.url)
            BottleVM.shared.bottlesList.paths.removeAll { $0 == bottle.url }
            BottleVM.shared.loadBottles()
            onDelete()
            dismiss()
        }
    }
}
