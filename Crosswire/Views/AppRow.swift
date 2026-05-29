//
//  AppRow.swift
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

/// One row in the library list. The discrete "Launch" button on the right is
/// the run affordance; clicking the row body opens the entry's detail view.
/// Right-click exposes the full set of per-entry actions.
struct AppRow: View {
    @ObservedObject var bottle: Bottle
    /// Run the entry's primary program (the Launch button, and the context
    /// menu's Launch item).
    let onRun: () -> Void
    /// Run a specific program chosen from the multi-launcher popover.
    let onRunSpecific: (Program) -> Void
    /// Open the entry's detail view (row-body click + "Show Details"). Today
    /// this is the per-app settings sheet; Section 2 swaps it for an inline
    /// `.entryDetail` destination.
    let onShowDetails: () -> Void
    /// Remove the entry (context menu "Uninstall…"). ContentView owns the
    /// confirmation + bottle-list mutation.
    let onUninstall: () -> Void
    /// Launch with full-lifetime diagnostics capture (context menu). Used to
    /// reproduce crashes; surfaces the run log + any JVM crash dump on exit.
    let onLaunchDiagnostics: () -> Void

    @State private var showProgramMenu: Bool = false
    @State private var hovered: Bool = false
    @State private var showRuntimesSheet: Bool = false
    @State private var isRenaming: Bool = false
    @State private var nameDraft: String = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        HStack(spacing: 14) {
            AppTileIcon(name: bottle.displayName)
            VStack(alignment: .leading, spacing: 3) {
                nameField
                Text(secondaryLine)
                    .font(CrosswireTheme.Typography.entryMeta)
                    .foregroundStyle(CrosswireTheme.textSecondary)
            }
            Spacer(minLength: 12)
            launchButton
        }
        .padding(.horizontal, 20)
        .frame(height: CrosswireTheme.Layout.libraryRowHeight)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovered ? CrosswireTheme.rowSurfaceHover : CrosswireTheme.rowSurface)
        )
        .scaleEffect(hovered ? 1.005 : 1.0)
        .animation(CrosswireTheme.Motion.hover, value: hovered)
        .onHover { hovered = $0 }
        .onTapGesture { if !isRenaming { onShowDetails() } }
        .contextMenu { contextMenu }
        .opacity(bottle.isAvailable ? 1.0 : 0.5)
        .sheet(isPresented: $showRuntimesSheet) {
            CommonRuntimesView(bottle: bottle)
        }
        .onAppear {
            if bottle.isAvailable && bottle.programs.isEmpty {
                bottle.updateInstalledPrograms()
            }
        }
    }

    /// Entry name, or an inline rename field when the user picks Rename from
    /// the context menu. Mirrors the sheet's rename: persists to
    /// `appDisplayName`; empty input clears the override.
    @ViewBuilder
    private var nameField: some View {
        if isRenaming {
            TextField("App name", text: $nameDraft)
                .textFieldStyle(.plain)
                .font(CrosswireTheme.Typography.entryName)
                .foregroundStyle(CrosswireTheme.textPrimary)
                .focused($nameFieldFocused)
                .onSubmit { commitRename() }
                .onExitCommand { isRenaming = false }
        } else {
            Text(bottle.displayName)
                .font(CrosswireTheme.Typography.entryName)
                .foregroundStyle(CrosswireTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button { onRun() } label: { Label("Launch", systemImage: "play.fill") }
            .disabled(!canLaunch)
        Button { onShowDetails() } label: { Label("Show Details", systemImage: "info.circle") }
        Button { beginRename() } label: { Label("Rename", systemImage: "pencil") }
        Button { showRuntimesSheet = true } label: { Label("Check Dependencies", systemImage: "shippingbox") }
        Button { revealInFinder() } label: { Label("Show in Finder", systemImage: "folder") }
        Button { onLaunchDiagnostics() } label: { Label("Launch with Diagnostics…", systemImage: "stethoscope") }
            .disabled(!canLaunch)
        Divider()
        Button(role: .destructive) { onUninstall() } label: { Label("Uninstall…", systemImage: "trash") }
    }

    /// The metadata line under the entry name. Currently:
    /// - "Setting up..." while the bottle is being provisioned (in-flight)
    /// - "Never launched" otherwise (placeholder until we add a
    ///   last-launched timestamp to BottleSettings — queued as observability
    ///   work; the brief calls for "Last played 2h ago" / "Never launched")
    private var secondaryLine: String {
        if bottle.inFlight { return "Setting up…" }
        return "Never launched"
    }

    private var canLaunch: Bool {
        !bottle.programs.isEmpty && bottle.isAvailable
    }

    /// Discrete blue "Launch" pill. With a single launcher it runs directly;
    /// with several it opens the picker popover. It's an explicit interactive
    /// child, so it blocks the row-body tap underneath it.
    @ViewBuilder
    private var launchButton: some View {
        Group {
            if bottle.userVisiblePrograms.count > 1 {
                Button { showProgramMenu = true } label: { launchLabel }
                    .popover(isPresented: $showProgramMenu, arrowEdge: .top) {
                        programPickerPopover
                    }
            } else {
                Button { onRun() } label: { launchLabel }
                    .disabled(!canLaunch)
            }
        }
        .buttonStyle(.plain)
        .help("Launch")
        .accessibilityLabel("Launch \(bottle.displayName)")
        .onTapGesture {}
    }

    @ViewBuilder
    private var launchLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "play.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("Launch")
                .font(CrosswireTheme.Typography.buttonPrimary)
        }
        .foregroundStyle(CrosswireTheme.textOnAccent)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(launchFill)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var launchFill: Color {
        guard canLaunch else { return CrosswireTheme.accent.opacity(0.30) }
        return hovered ? CrosswireTheme.accentHover : CrosswireTheme.accent
    }

    // MARK: - Context-menu actions

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

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([bottle.url])
    }

    private var programPickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Run…")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CrosswireTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            ForEach(bottle.userVisiblePrograms) { program in
                Button {
                    showProgramMenu = false
                    onRunSpecific(program)
                } label: {
                    HStack {
                        Text(program.name.replacingOccurrences(of: ".exe", with: ""))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(minWidth: 200)
        .padding(.vertical, 4)
    }
}
