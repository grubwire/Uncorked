//
//  EngineDownloadView.swift
//  Uncorked
//
//  This file is part of Uncorked.
//
//  Uncorked is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Uncorked is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Uncorked.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI
import UncorkedKit

// MARK: - Gcenx GitHub Release API models

struct GcenxRelease: Codable {
    let tagName: String
    let assets: [GcenxAsset]
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

struct GcenxAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
    }
}

enum UncorkError: Error {
    case noSuitableAsset
    case invalidURL
}

// MARK: - Gcenx release fetch

private let gcenxReleasesAPI = "https://api.github.com/repos/Gcenx/macOS_Wine_builds/releases/latest"

func fetchLatestGcenxRelease() async throws -> GcenxRelease {
    guard let apiURL = URL(string: gcenxReleasesAPI) else {
        throw UncorkError.invalidURL
    }
    var request = URLRequest(url: apiURL)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    let (data, _) = try await URLSession.shared.data(for: request)
    return try JSONDecoder().decode(GcenxRelease.self, from: data)
}

func fetchLatestWineDownloadURL() async throws -> (URL, String) {
    let release = try await fetchLatestGcenxRelease()
    let tarAssets = release.assets.filter { $0.name.hasSuffix(".tar.xz") }
    let asset = tarAssets.first(where: { $0.name.contains("wine-stable") })
        ?? tarAssets.first(where: { $0.name.contains("wine-staging") })
        ?? tarAssets.first(where: { $0.name.contains("wine-devel") })
        ?? tarAssets.first
    guard let asset = asset else {
        throw UncorkError.noSuitableAsset
    }
    guard let url = URL(string: asset.browserDownloadUrl) else {
        throw UncorkError.invalidURL
    }
    return (url, release.tagName)
}

// MARK: - Download view

struct EngineDownloadView: View {
    @State private var fractionProgress: Double = 0
    @State private var completedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var downloadSpeed: Double = 0
    @State private var downloadTask: URLSessionDownloadTask?
    @State private var observation: NSKeyValueObservation?
    @State private var startTime: Date?
    @State private var errorMessage: String?
    @Binding var tarLocation: URL
    @Binding var wineTagName: String
    @Binding var path: [SetupStage]
    var body: some View {
        VStack {
            VStack {
                Text("setup.engine.download")
                    .font(.title)
                    .fontWeight(.bold)
                Text("setup.engine.download.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                        .padding(.horizontal)
                } else {
                    VStack {
                        ProgressView(value: fractionProgress, total: 1)
                        HStack {
                            HStack {
                                Text(String(format: String(localized: "setup.engine.progress"),
                                            formatBytes(bytes: completedBytes),
                                            formatBytes(bytes: totalBytes)))
                                + Text(String(" "))
                                + (shouldShowEstimate() ?
                                   Text(String(format: String(localized: "setup.engine.eta"),
                                               formatRemainingTime(remainingBytes: totalBytes - completedBytes)))
                                   : Text(String()))
                                Spacer()
                            }
                            .font(.subheadline)
                            .monospacedDigit()
                        }
                    }
                    .padding(.horizontal)
                }
                Spacer()
            }
            Spacer()
        }
        .frame(width: 400, height: 200)
        .onAppear {
            Task {
                do {
                    let (downloadURL, tagName) = try await fetchLatestWineDownloadURL()
                    await MainActor.run { wineTagName = tagName }
                    downloadTask = URLSession(configuration: .ephemeral).downloadTask(with: downloadURL) { url, _, _ in
                        Task.detached {
                            await MainActor.run {
                                if let url = url {
                                    tarLocation = url
                                    proceed()
                                }
                            }
                        }
                    }
                    observation = downloadTask?.observe(\.countOfBytesReceived) { task, _ in
                        Task {
                            await MainActor.run {
                                let currentTime = Date()
                                let elapsedTime = currentTime.timeIntervalSince(startTime ?? currentTime)
                                if completedBytes > 0 {
                                    downloadSpeed = Double(completedBytes) / elapsedTime
                                }
                                totalBytes = task.countOfBytesExpectedToReceive
                                completedBytes = task.countOfBytesReceived
                                fractionProgress = Double(completedBytes) / Double(totalBytes)
                            }
                        }
                    }
                    startTime = Date()
                    downloadTask?.resume()
                } catch {
                    await MainActor.run {
                        errorMessage = "Failed to fetch Wine download URL: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    func formatBytes(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = true
        return formatter.string(fromByteCount: bytes)
    }

    func shouldShowEstimate() -> Bool {
        let elapsedTime = Date().timeIntervalSince(startTime ?? Date())
        return Int(elapsedTime.rounded()) > 5 && completedBytes != 0
    }

    func formatRemainingTime(remainingBytes: Int64) -> String {
        let remainingTimeInSeconds = Double(remainingBytes) / downloadSpeed

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .full
        if shouldShowEstimate() {
            return formatter.string(from: TimeInterval(remainingTimeInSeconds)) ?? ""
        } else {
            return ""
        }
    }

    func proceed() {
        path.append(.engineInstall)
    }
}
