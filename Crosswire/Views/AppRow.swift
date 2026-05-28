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
import CrosswireKit

/// One row in the library list. Click anywhere on the row to run the entry's
/// primary program (the row IS the run affordance — that's its job). The
/// gear button on the right opens settings; it's smaller and secondary.
struct AppRow: View {
    @ObservedObject var bottle: Bottle
    /// Tap on the row body. Currently routed to onRun by ContentView so the
    /// row's primary affordance is "click to run." Kept as a separate
    /// callback so ContentView can rewire it (e.g. to a future selection
    /// model) without touching this view.
    let onPrimaryAction: () -> Void
    let onRun: () -> Void
    let onRunSpecific: (Program) -> Void
    let onOpenSettings: () -> Void

    @State private var showProgramMenu: Bool = false
    @State private var hovered: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            AppTileIcon(name: bottle.displayName)
            VStack(alignment: .leading, spacing: 3) {
                Text(bottle.displayName)
                    .font(CrosswireTheme.Typography.entryName)
                    .foregroundStyle(CrosswireTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(secondaryLine)
                    .font(CrosswireTheme.Typography.entryMeta)
                    .foregroundStyle(CrosswireTheme.textSecondary)
            }
            Spacer(minLength: 12)
            controls
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
        .onTapGesture { onPrimaryAction() }
        .opacity(bottle.isAvailable ? 1.0 : 0.5)
        .onAppear {
            if bottle.isAvailable && bottle.programs.isEmpty {
                bottle.updateInstalledPrograms()
            }
        }
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

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 8) {
            playButton
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(CrosswireTheme.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        // Buttons are explicit interactive children — they must not let the
        // row's `onTapGesture` fire underneath them.
        .onTapGesture {}
    }

    @ViewBuilder
    private var playButton: some View {
        let visible = bottle.userVisiblePrograms
        if visible.count > 1 {
            Button {
                showProgramMenu = true
            } label: {
                playLabel
            }
            .buttonStyle(.borderless)
            .help("Run")
            .popover(isPresented: $showProgramMenu, arrowEdge: .top) {
                programPickerPopover
            }
        } else {
            Button {
                onRun()
            } label: {
                playLabel
            }
            .buttonStyle(.borderless)
            .disabled(bottle.programs.isEmpty || !bottle.isAvailable)
            .help("Run")
        }
    }

    /// Play affordance. Larger + more prominent than before per Brief 2 —
    /// 34pt circle, accent-blue fill on row hover, soft accent-tinted ring
    /// at rest so it always reads as "the run button" even before hover.
    @ViewBuilder
    private var playLabel: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(hovered ? CrosswireTheme.textOnAccent : CrosswireTheme.accent)
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(hovered ? CrosswireTheme.accent : CrosswireTheme.accent.opacity(0.12))
            )
            .overlay(
                Circle()
                    .strokeBorder(CrosswireTheme.accent.opacity(hovered ? 0 : 0.25), lineWidth: 1)
            )
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
