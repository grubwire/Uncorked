//
//  EngineSetupView.swift
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

struct EngineSetupView: View {
    @State private var phase: Phase = .fetchingManifest
    @State private var completedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var downloadSpeed: Double = 0
    @State private var downloadStartTime: Date?
    @State private var errorMessage: String?
    @Binding var showSetup: Bool

    enum Phase: Equatable {
        case fetchingManifest
        case downloading
        case verifying
        case installing
        case done
    }

    var body: some View {
        VStack {
            VStack {
                Text(phase == .downloading ? "setup.engine.download" : "setup.engine.install")
                    .font(.title)
                    .fontWeight(.bold)
                Text("setup.engine.install.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let errorMessage {
                    VStack(spacing: 8) {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button("setup.retry") {
                            self.errorMessage = nil
                            startSetup()
                        }
                    }
                } else if phase == .done {
                    Image(systemName: "checkmark.circle")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.green)
                } else if phase == .downloading && totalBytes > 0 {
                    VStack {
                        ProgressView(value: Double(completedBytes), total: Double(totalBytes))
                        HStack {
                            Text(String(format: String(localized: "setup.engine.progress"),
                                        formatBytes(completedBytes),
                                        formatBytes(totalBytes)))
                            + Text(" ")
                            + (shouldShowETA() ?
                               Text(String(format: String(localized: "setup.engine.eta"),
                                           formatRemainingTime()))
                               : Text(""))
                            Spacer()
                        }
                        .font(.subheadline)
                        .monospacedDigit()
                    }
                    .padding(.horizontal)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 80)
                }
                Spacer()
            }
            Spacer()
        }
        .frame(width: 400, height: 200)
        .onAppear {
            startSetup()
        }
    }

    private func startSetup() {
        phase = .fetchingManifest
        completedBytes = 0
        totalBytes = 0
        downloadSpeed = 0
        downloadStartTime = nil

        Task.detached {
            do {
                let manifest = try await CrosswireEngine.fetchManifest()

                await MainActor.run {
                    phase = .downloading
                    downloadStartTime = Date()
                }

                let archive = try await CrosswireEngine.downloadArchive(manifest: manifest) { written, total in
                    Task { @MainActor in
                        let elapsed = Date().timeIntervalSince(downloadStartTime ?? Date())
                        if written > 0 && elapsed > 0 {
                            downloadSpeed = Double(written) / elapsed
                        }
                        completedBytes = written
                        if total > 0 { totalBytes = total }
                    }
                }

                await MainActor.run { phase = .verifying }
                try await CrosswireEngine.verifyAndInstall(archive: archive, manifest: manifest)
                await MainActor.run { phase = .done }

                try await Task.sleep(for: .seconds(2))
                await MainActor.run { showSetup = false }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = true
        return formatter.string(fromByteCount: bytes)
    }

    private func shouldShowETA() -> Bool {
        let elapsed = Date().timeIntervalSince(downloadStartTime ?? Date())
        return elapsed > 5 && completedBytes > 0 && downloadSpeed > 0
    }

    private func formatRemainingTime() -> String {
        let remaining = Double(totalBytes - completedBytes) / downloadSpeed
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        return formatter.string(from: TimeInterval(remaining)) ?? ""
    }
}
