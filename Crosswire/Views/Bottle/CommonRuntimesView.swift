//
//  CommonRuntimesView.swift
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

/// Curated common-runtime installer. Lets the user opt in to the Windows
/// dependencies that most installers expect (VC++, .NET, fonts, DirectX)
/// without having to wade through the full Winetricks catalogue.
///
/// Selected verbs are chained into a single `winetricks` invocation so the
/// user gets one Terminal session instead of one per runtime.
struct CommonRuntimesView: View {
    let bottle: Bottle
    @Environment(\.dismiss) private var dismiss

    @State private var selection: Set<String> = Set(RuntimeCatalogue.essentials.map(\.verb))

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider().opacity(0.5)
                list
                Divider().opacity(0.5)
                footer
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .windowToolbar)
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 540, idealHeight: 600)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Install common runtimes")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            Text("Windows installers often expect Microsoft fonts, Visual C++ runtimes, "
                 + ".NET, and DirectX to already be present. Select what to add — they "
                 + "install once into this app's environment.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section(title: "Recommended", items: RuntimeCatalogue.essentials)
                section(title: "Optional", items: RuntimeCatalogue.optional)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func section(title: String, items: [RuntimePreset]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, preset in
                    presetRow(preset)
                    if index < items.count - 1 {
                        Divider()
                            .opacity(0.4)
                            .padding(.leading, 48)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
    }

    private func presetRow(_ preset: RuntimePreset) -> some View {
        let selected = selection.contains(preset.verb)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.25), lineWidth: 1.25)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(selected ? Color.accentColor : Color.clear)
                    )
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(preset.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(preset.verb)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Text(preset.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            if selected {
                selection.remove(preset.verb)
            } else {
                selection.insert(preset.verb)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(selectionSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Install \(selection.count)") {
                install()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selection.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var selectionSummary: String {
        if selection.isEmpty {
            return "Nothing selected"
        }
        if selection.count == 1 {
            return "1 runtime selected"
        }
        return "\(selection.count) runtimes selected"
    }

    private func install() {
        // Run verbs in catalogue order so a stable installation sequence
        // results regardless of how the user toggled them.
        let ordered = RuntimeCatalogue.all
            .map(\.verb)
            .filter { selection.contains($0) }
        guard !ordered.isEmpty else { return }
        let command = ordered.joined(separator: " ")
        Task {
            await Winetricks.runCommand(command: command, bottle: bottle)
        }
        dismiss()
    }
}
