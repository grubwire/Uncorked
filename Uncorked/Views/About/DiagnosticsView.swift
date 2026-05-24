//
//  DiagnosticsView.swift
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

/// Shows technical state: app version, engine version, and beta channel state.
/// Present from the first release so bug reports include this info.
struct DiagnosticsView: View {
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var engineState: CrosswireKit.InstalledEngineVersion? {
        CrosswireEngine.installedEngineState()
    }

    var body: some View {
        Form {
            Section("App") {
                DiagnosticRow(label: "Version", value: appVersion)
            }

            Section("Engine") {
                if let state = engineState {
                    DiagnosticRow(label: "Version", value: state.engineVersion)
                    DiagnosticRow(label: "Upstream tag", value: state.upstreamTag)
                } else {
                    DiagnosticRow(label: "Version", value: "Not installed")
                }
            }

            Section("Updates") {
                // Stage 1: beta channel not yet built. Placeholder shows "off".
                // Wire to the real toggle when the beta system is built (Part 2).
                DiagnosticRow(label: "Beta channel", value: "off")
            }

            Section("Paths") {
                DiagnosticRow(label: "Engine", value: CrosswireEngine.engineFolder.path)
                DiagnosticRow(label: "Libraries", value: CrosswireEngine.libraryFolder.path)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 320)
        .navigationTitle("Diagnostics")
    }
}

// MARK: - Supporting views

private struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }
}
