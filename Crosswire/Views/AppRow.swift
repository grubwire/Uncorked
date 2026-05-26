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

/// One row in the main app list. Single-click opens settings (the more
/// discoverable target), double-click runs the primary program.
struct AppRow: View {
    @ObservedObject var bottle: Bottle
    let onPrimaryAction: () -> Void
    let onRun: () -> Void
    let onRunSpecific: (Program) -> Void
    let onOpenSettings: () -> Void

    @State private var showProgramMenu: Bool = false
    @State private var hovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            AppTileIcon(name: bottle.settings.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(bottle.settings.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                if bottle.programs.count > 1 {
                    Text("\(bottle.programs.count) programs")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if bottle.inFlight {
                    Text("Setting up...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            controls
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .background(hovered ? Color.primary.opacity(0.05) : Color.clear)
        .onHover { hovered = $0 }
        .onTapGesture(count: 2) { onRun() }
        .onTapGesture { onPrimaryAction() }
        .opacity(bottle.isAvailable ? 1.0 : 0.5)
        .onAppear {
            // Pull the program list so "X programs" is accurate without
            // requiring the user to open the settings sheet first.
            if bottle.isAvailable && bottle.programs.isEmpty {
                bottle.updateInstalledPrograms()
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 4) {
            playButton
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        // Stop the row's tap gestures from firing when the user clicks the
        // buttons directly.
        .onTapGesture {}
    }

    @ViewBuilder
    private var playButton: some View {
        if bottle.programs.count > 1 {
            Button {
                showProgramMenu = true
            } label: {
                Image(systemName: "play.fill")
                    .frame(width: 28, height: 28)
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
                Image(systemName: "play.fill")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(bottle.programs.isEmpty || !bottle.isAvailable)
            .help("Run")
        }
    }

    private var programPickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Run...")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            ForEach(bottle.programs) { program in
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
