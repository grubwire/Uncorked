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

// swiftlint:disable type_body_length
// Per-app settings sheet. Default view is name + Run + Uninstall. Anything
// that exposes the underlying Wine prefix (path, Windows version, DXVK,
// raw exe list) lives behind the Advanced disclosure.
struct AppSettingsSheet: View {
    @ObservedObject var bottle: Bottle
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var primarySelection: URL?
    @State private var showAdvanced: Bool = false
    @State private var showRuntimesSheet: Bool = false
    @State private var isEditingName: Bool = false
    @State private var nameDraft: String = ""

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
                    if isEditingName {
                        TextField("App name", text: $nameDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 14, weight: .semibold))
                            .onSubmit { commitRename() }
                            .submitLabel(.done)
                            .onExitCommand { isEditingName = false }
                    } else {
                        HStack(spacing: 6) {
                            Text(bottle.displayName)
                                .font(.system(size: 16, weight: .semibold))
                                .lineLimit(1)
                            Button {
                                nameDraft = bottle.displayName
                                isEditingName = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Rename app")
                        }
                    }
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
        sectionLabel("Configuration")
        LabeledContent("Windows version") {
            Picker("", selection: $bottle.settings.windowsVersion) {
                ForEach(WinVersion.allCases.reversed(), id: \.self) {
                    Text($0.pretty()).tag($0)
                }
            }
            .labelsHidden()
        }
        Toggle("DXVK (DirectX to Vulkan)", isOn: $bottle.settings.dxvk)
        LabeledContent("Installed at") {
            Text(bottle.url.prettyPath())
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }

        sectionLabel("Apps")
        LabeledContent("Primary launcher") {
            Picker("", selection: $primarySelection) {
                Text("None").tag(URL?.none)
                ForEach(bottle.programs) { program in
                    Text(program.name.replacingOccurrences(of: ".exe", with: ""))
                        .tag(Optional(program.url))
                }
            }
            .labelsHidden()
            .onChange(of: primarySelection) { _, newValue in
                bottle.settings.primaryProgramURL = newValue
            }
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
                            .controlSize(.small)
                    }
                }
            }
        }

        sectionLabel("Maintenance")
        actionRow(systemImage: "shippingbox",
                  title: "Install common runtimes…",
                  help: "Adds Microsoft fonts, Visual C++, .NET, and DirectX to this app's environment") {
            showRuntimesSheet = true
        }
        actionRow(systemImage: "arrow.clockwise",
                  title: "Rescan installed programs") {
            bottle.finalizeAppIdentity()
        }
        actionRow(systemImage: "folder",
                  title: "Open in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([bottle.url])
        }
        actionRow(systemImage: "terminal",
                  title: "Open Terminal") {
            bottle.openTerminal()
        }
        actionRow(systemImage: "play.square",
                  title: "Run a .exe inside this app…") {
            pickAdHocExecutable()
        }
    }

    @ViewBuilder
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.7)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func actionRow(
        systemImage: String, title: String, help: String? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help ?? title)
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

    /// Persist the renamed app display name to the bottle. Empty / unchanged
    /// input clears the override so the bottle falls back to its detected
    /// name. Trims whitespace.
    private func commitRename() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingName = false
        if trimmed.isEmpty {
            bottle.settings.appDisplayName = nil
        } else if trimmed != bottle.displayName {
            bottle.settings.appDisplayName = trimmed
        }
    }

    private func pickAdHocExecutable() {
        // NOTE(backlog): this path does NOT invoke JavaAppDetector. If the
        // user picks a self-contained JavaFX launcher here (rather than via
        // the create-new-bottle install flow), the per-program plist + the
        // bottle's dwrite=builtin override are never seeded automatically.
        // Workaround: install Java apps through "Install Windows App" so a
        // fresh bottle is created. Fix is to call JavaAppDetector.applyDefaults
        // here too, gated on first-time selection per .exe.
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
// swiftlint:enable type_body_length
