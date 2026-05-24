//
//  AboutView.swift
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

struct AboutView: View {
    @Environment(\.openURL) private var openURL

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // App identity
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)

                Text("Uncorked")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Version \(appVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Copyright 2024-2026 Grubwire. All rights reserved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            // Acknowledgements
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Acknowledgements")
                        .font(.headline)
                        .padding(.top, 4)

                    AcknowledgementRow(
                        title: "Inspired by Whisky",
                        detail: "Uncorked is a fork of Whisky, an open source Wine wrapper for macOS. "
                            + "Whisky laid the groundwork this app builds on.",
                        url: "https://github.com/Whisky-App/Whisky"
                    )

                    AcknowledgementRow(
                        title: "Wine",
                        detail: "The Windows compatibility layer. "
                            + "Licensed under LGPL-2.1 and other open source licenses. "
                            + "Wine is not affiliated with or endorsed by Microsoft.",
                        url: "https://www.winehq.org"
                    )

                    AcknowledgementRow(
                        title: "Gcenx macOS Wine builds",
                        detail: "Pre-built Wine binaries optimized for macOS and Apple Silicon, "
                            + "maintained by the Gcenx project.",
                        url: "https://github.com/Gcenx/macOS_Wine_builds"
                    )

                    AcknowledgementRow(
                        title: "DXVK",
                        detail: "A Vulkan-based translation layer for Direct3D 9, 10, and 11. "
                            + "Licensed under the zlib license.",
                        url: "https://github.com/doitsujin/dxvk"
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            Divider()

            // License and links
            HStack(spacing: 16) {
                Button("GPL-3.0 License") {
                    if let url = URL(string: "https://github.com/grubwire/uncorked/blob/main/LICENSE") {
                        openURL(url)
                    }
                }
                .buttonStyle(.link)

                Button("Source Code") {
                    if let url = URL(string: "https://github.com/grubwire/uncorked") {
                        openURL(url)
                    }
                }
                .buttonStyle(.link)
            }
            .font(.caption)
            .padding(.vertical, 12)
        }
        .frame(width: 440, height: 520)
    }
}

// MARK: - Supporting views

private struct AcknowledgementRow: View {
    let title: String
    let detail: String
    let url: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(title) {
                if let linkURL = URL(string: url) { openURL(linkURL) }
            }
            .buttonStyle(.link)
            .font(.subheadline)
            .fontWeight(.medium)

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
