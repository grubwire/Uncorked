//
//  EntryDetailView.swift
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

// swiftlint:disable type_body_length file_length
/// Full-bleed inline per-entry detail shown when `AppRoute == .entryDetail`.
/// Slides in over the library (same pattern as inline Settings); the back
/// chevron returns. Replaces the old detached `AppSettingsSheet` modal.
///
/// This is a transient overlay, so it sits on a `.regularMaterial` blur over
/// the library shell (materials-vs-hex rule). Launch + run-specific routes go
/// back out through ContentView's run helpers so single-instance handling
/// (Commit 6) applies uniformly.
struct EntryDetailView: View {
    @ObservedObject var bottle: Bottle
    var onBack: () -> Void
    var onRun: () -> Void
    var onRunProgram: (Program) -> Void
    var onUninstall: () -> Void

    @State private var showRuntimesSheet: Bool = false
    @State private var isRenaming: Bool = false
    @State private var nameDraft: String = ""
    @State private var showAdvanced: Bool = false
    @State private var primarySelection: URL?
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            navBar
            Divider().opacity(0.3)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    launchButton
                    secondaryActions
                    advancedDisclosure
                }
                .padding(28)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(.regularMaterial)
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

    // MARK: - Nav bar

    private var navBar: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Library")
                        .font(CrosswireTheme.Typography.body)
                }
                .foregroundStyle(CrosswireTheme.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Back to Library")
            .accessibilityLabel("Back to Library")
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(spacing: 16) {
            AppTileIcon(name: bottle.displayName, side: 72)
            VStack(alignment: .leading, spacing: 6) {
                nameField
                Text(categoryLine)
                    .font(CrosswireTheme.Typography.body)
                    .foregroundStyle(CrosswireTheme.textSecondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var nameField: some View {
        if isRenaming {
            TextField("App name", text: $nameDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(CrosswireTheme.textPrimary)
                .focused($nameFieldFocused)
                .onSubmit { commitRename() }
                .onExitCommand { isRenaming = false }
                .frame(maxWidth: 360)
        } else {
            HStack(spacing: 8) {
                Text(bottle.displayName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(CrosswireTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button(action: beginRename) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(CrosswireTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Rename")
                .accessibilityLabel("Rename")
            }
        }
    }

    private var categoryLine: String {
        let count = bottle.userVisiblePrograms.count
        if count > 1 { return "Windows app · \(count) launchers" }
        return "Windows app"
    }

    // MARK: - Launch

    private var canLaunch: Bool {
        !bottle.programs.isEmpty && bottle.isAvailable
    }

    private var launchButton: some View {
        Button(action: onRun) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Launch")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(CrosswireTheme.textOnAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(canLaunch ? CrosswireTheme.accent : CrosswireTheme.accent.opacity(0.30))
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canLaunch)
        .accessibilityLabel("Launch \(bottle.displayName)")
    }

    // MARK: - Secondary actions

    private var secondaryActions: some View {
        HStack(spacing: 10) {
            secondaryButton("Check Dependencies", systemImage: "shippingbox") {
                showRuntimesSheet = true
            }
            secondaryButton("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([bottle.url])
            }
            secondaryButton("Uninstall", systemImage: "trash", destructive: true) {
                onUninstall()
            }
        }
    }

    @ViewBuilder
    private func secondaryButton(
        _ title: String, systemImage: String, destructive: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(CrosswireTheme.Typography.buttonLabel)
            }
            .foregroundStyle(destructive ? CrosswireTheme.danger : CrosswireTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CrosswireTheme.rowSurface)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: - Advanced

    @ViewBuilder
    private var advancedDisclosure: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 16) {
                advancedConfiguration
                advancedApps
                advancedMaintenance
            }
            .padding(.top, 12)
        } label: {
            Text("Advanced")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CrosswireTheme.textPrimary)
        }
        .tint(CrosswireTheme.accent)
    }

    @ViewBuilder
    private var advancedConfiguration: some View {
        advancedHeader("Configuration")
        HStack {
            Text("Windows version")
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textPrimary)
            Spacer()
            Picker("", selection: $bottle.settings.windowsVersion) {
                ForEach(WinVersion.allCases.reversed(), id: \.self) {
                    Text($0.pretty()).tag($0)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 160)
        }
        Toggle("DXVK (DirectX to Vulkan)", isOn: $bottle.settings.dxvk)
            .tint(CrosswireTheme.accent)
            .font(CrosswireTheme.Typography.body)
            .foregroundStyle(CrosswireTheme.textPrimary)
        VStack(alignment: .leading, spacing: 4) {
            Text("Installed at")
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textPrimary)
            Text(bottle.url.prettyPath())
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(CrosswireTheme.textSecondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var advancedApps: some View {
        advancedHeader("Apps")
        HStack {
            Text("Primary launcher")
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textPrimary)
            Spacer()
            Picker("", selection: $primarySelection) {
                Text("None").tag(URL?.none)
                ForEach(bottle.programs) { program in
                    Text(program.name.replacingOccurrences(of: ".exe", with: ""))
                        .tag(Optional(program.url))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220)
            .onChange(of: primarySelection) { _, newValue in
                bottle.settings.primaryProgramURL = newValue
            }
        }
        if !bottle.programs.isEmpty {
            DisclosureGroup("All installed programs (\(bottle.programs.count))") {
                ForEach(bottle.programs) { program in
                    HStack {
                        Text(program.name.replacingOccurrences(of: ".exe", with: ""))
                            .font(CrosswireTheme.Typography.body)
                            .foregroundStyle(CrosswireTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Run") { onRunProgram(program) }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                    }
                }
            }
            .tint(CrosswireTheme.accent)
        }
    }

    @ViewBuilder
    private var advancedMaintenance: some View {
        advancedHeader("Maintenance")
        maintenanceRow("arrow.clockwise", "Rescan installed programs") {
            bottle.finalizeAppIdentity()
        }
        maintenanceRow("terminal", "Open Terminal") {
            bottle.openTerminal()
        }
        maintenanceRow("play.square", "Run a .exe inside this app…") {
            pickAdHocExecutable()
        }
    }

    @ViewBuilder
    private func advancedHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.7)
            .foregroundStyle(CrosswireTheme.textTertiary)
            .padding(.top, 4)
    }

    @ViewBuilder
    private func maintenanceRow(_ systemImage: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(CrosswireTheme.textSecondary)
                    .frame(width: 16)
                Text(title)
                    .font(CrosswireTheme.Typography.body)
                    .foregroundStyle(CrosswireTheme.textPrimary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: - Actions

    private func beginRename() {
        nameDraft = bottle.displayName
        isRenaming = true
        DispatchQueue.main.async { nameFieldFocused = true }
    }

    private func commitRename() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isRenaming = false
        if trimmed.isEmpty {
            bottle.settings.appDisplayName = nil
        } else if trimmed != bottle.displayName {
            bottle.settings.appDisplayName = trimmed
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
                await JavaAppDetector.applyDefaultsIfNeeded(forExeAt: url, in: bottle)
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
}
// swiftlint:enable type_body_length file_length
