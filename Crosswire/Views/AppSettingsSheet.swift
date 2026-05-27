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

/// Per-app settings sheet. Default view is name + Run + Uninstall. Anything
/// that exposes the underlying Wine prefix (path, Windows version, DXVK,
/// raw exe list) lives behind the Advanced disclosure.
struct AppSettingsSheet: View {
    @ObservedObject var bottle: Bottle
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var primarySelection: URL?
    @State private var showAdvanced: Bool = false
    @State private var showRuntimesSheet: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                primarySection
                Section {
                    DisclosureGroup(isExpanded: $showAdvanced) {
                        advancedContent
                    } label: {
                        Text("Advanced")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(bottle.displayName)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
        .sheet(isPresented: $showRuntimesSheet) {
            CommonRuntimesView(bottle: bottle)
        }
        .onAppear {
            primarySelection = bottle.settings.primaryProgramURL
            if bottle.programs.isEmpty {
                bottle.updateInstalledPrograms()
            }
        }
    }

    @ViewBuilder
    private var primarySection: some View {
        Section {
            HStack(spacing: 12) {
                AppTileIcon(name: bottle.displayName)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bottle.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    if bottle.userVisiblePrograms.count > 1 {
                        Text("^[\(bottle.userVisiblePrograms.count) launcher](inflect: true)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)

            Button {
                runPrimaryFromSheet()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("Run")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!bottle.isAvailable || resolvedPrimaryProgram == nil)

            Button(role: .destructive) {
                confirmDelete()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Uninstall")
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var advancedContent: some View {
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

        if !bottle.programs.isEmpty {
            DisclosureGroup("All installed programs (\(bottle.programs.count))") {
                ForEach(bottle.programs) { program in
                    HStack {
                        Text(program.name.replacingOccurrences(of: ".exe", with: ""))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Run") { runProgram(program) }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }

        Button {
            showRuntimesSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox")
                Text("Install common runtimes…")
            }
        }
        .help("Adds Microsoft fonts, Visual C++, .NET, and DirectX to this app's environment")

        Button("Rescan installed programs") {
            bottle.finalizeAppIdentity()
        }
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

    private var resolvedPrimaryProgram: Program? {
        if let url = bottle.settings.primaryProgramURL,
           let match = bottle.programs.first(where: { $0.url == url }) {
            return match
        }
        if let first = bottle.userVisiblePrograms.first { return first }
        return bottle.programs.first
    }

    private func runPrimaryFromSheet() {
        guard let program = resolvedPrimaryProgram else { return }
        runProgram(program)
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
        alert.messageText = "Uninstall \(bottle.displayName)?"
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
