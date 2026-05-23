//
//  UncorkedEngine.swift
//  UncorkedKit
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

import Foundation
import SemanticVersion

private struct GcenxRelease: Codable {
    let tagName: String
    let assets: [GcenxAsset]
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct GcenxAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
    }
}

public class UncorkedEngine {
    /// The Uncorked application folder
    public static let applicationFolder = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appending(path: Bundle.uncorkedBundleIdentifier)

    /// The folder of all the library files
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// URL to the installed `wine` `bin` directory
    public static let binFolder: URL = libraryFolder.appending(path: "Wine").appending(path: "bin")

    // MARK: - Gcenx GitHub API

    private static let gcenxReleasesAPI = "https://api.github.com/repos/Gcenx/macOS_Wine_builds/releases/latest"

    /// Fetch the latest Gcenx release tag (e.g. "11.9" → SemanticVersion(11, 9, 0))
    private static func fetchLatestGcenxVersion() async -> SemanticVersion? {
        guard let apiURL = URL(string: gcenxReleasesAPI) else { return nil }
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return await withCheckedContinuation { continuation in
            URLSession(configuration: .ephemeral).dataTask(with: request) { data, _, error in
                guard error == nil, let data = data else {
                    continuation.resume(returning: nil)
                    return
                }
                do {
                    let release = try JSONDecoder().decode(GcenxRelease.self, from: data)
                    let version = Self.parseGcenxTag(release.tagName)
                    continuation.resume(returning: version)
                } catch {
                    print("Failed to decode Gcenx release: \(error)")
                    continuation.resume(returning: nil)
                }
            }.resume()
        }
    }

    /// Parse Gcenx tag format: "wine-stable-11.9" or plain "11.9" → SemanticVersion(11, 9, 0)
    static func parseGcenxTag(_ tag: String) -> SemanticVersion? {
        // Strip any non-numeric prefix (e.g. "wine-stable-")
        let stripped = tag.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }
        guard let major = stripped.first.flatMap({ Int($0) }),
              let minor = stripped.dropFirst().first.flatMap({ Int($0) }) else {
            return nil
        }
        let patch = stripped.dropFirst(2).first.flatMap { Int($0) } ?? 0
        return SemanticVersion(major, minor, patch)
    }

    // MARK: - Public API

    public static func isEnginePresent() -> Bool {
        return engineVersion() != nil
    }

    /// Install the engine from a downloaded tar.xz at `from`.
    /// Gcenx archives contain a top-level folder (e.g. "Wine Stable/").
    /// We find the extracted folder containing bin/wine64 and move it to Libraries/Wine/.
    public static func install(from: URL, tagName: String? = nil) async {
        do {
            // Ensure a clean application folder
            if FileManager.default.fileExists(atPath: applicationFolder.path) {
                try FileManager.default.removeItem(at: applicationFolder)
            }
            try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)

            // Extract to a temp directory
            let tempDir = applicationFolder.appending(path: "_extract_tmp")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try Tar.untar(tarBall: from, toURL: tempDir)
            try? FileManager.default.removeItem(at: from)

            // Find the extracted Wine folder (the one containing bin/wine64 or bin/wine)
            let extracted = try FileManager.default.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
            )
            guard let wineRoot = extracted.first(where: { url in
                let hasBin = FileManager.default.fileExists(
                    atPath: url.appending(path: "bin/wine64").path
                ) || FileManager.default.fileExists(
                    atPath: url.appending(path: "bin/wine").path
                )
                return hasBin
            }) else {
                guard let first = extracted.first else {
                    print("UncorkedEngine: no extracted directory found")
                    return
                }
                try moveEngineRoot(first, tempDir: tempDir, tagName: tagName)
                return
            }

            try moveEngineRoot(wineRoot, tempDir: tempDir, tagName: tagName)
        } catch {
            print("Failed to install engine: \(error)")
        }
    }

    private static func moveEngineRoot(_ wineRoot: URL, tempDir: URL, tagName: String?) throws {
        let wineDestination = libraryFolder.appending(path: "Wine")
        try FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: wineDestination.path) {
            try FileManager.default.removeItem(at: wineDestination)
        }
        try FileManager.default.moveItem(at: wineRoot, to: wineDestination)

        try? FileManager.default.removeItem(at: tempDir)

        let version: SemanticVersion
        if let tag = tagName, let parsed = parseGcenxTag(tag) {
            version = parsed
        } else {
            version = SemanticVersion(0, 0, 0)
        }
        try writeVersionPlist(version)
    }

    private static func writeVersionPlist(_ version: SemanticVersion) throws {
        let versionPlist = libraryFolder
            .appending(path: "UncorkedEngineVersion")
            .appendingPathExtension("plist")
        let info = UncorkedEngineVersion(version: version)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(info)
        try data.write(to: versionPlist)
    }

    public static func uninstall() {
        do {
            try FileManager.default.removeItem(at: libraryFolder)
        } catch {
            print("Failed to uninstall engine: \(error)")
        }
    }

    /// Check whether a newer Gcenx build is available.
    public static func shouldUpdateEngine() async -> (Bool, SemanticVersion) {
        let localVersion = engineVersion()
        let remoteVersion = await fetchLatestGcenxVersion()

        if let localVersion = localVersion, let remoteVersion = remoteVersion {
            if localVersion < remoteVersion {
                return (true, remoteVersion)
            }
        }

        return (false, SemanticVersion(0, 0, 0))
    }

    public static func engineVersion() -> SemanticVersion? {
        do {
            let versionPlist = libraryFolder
                .appending(path: "UncorkedEngineVersion")
                .appendingPathExtension("plist")

            let decoder = PropertyListDecoder()
            let data = try Data(contentsOf: versionPlist)
            let info = try decoder.decode(UncorkedEngineVersion.self, from: data)
            return info.version
        } catch {
            // Also check legacy plist name from pre-rename installs
            do {
                let legacyPlist = libraryFolder
                    .appending(path: "UncorkedWineVersion")
                    .appendingPathExtension("plist")
                let decoder = PropertyListDecoder()
                let data = try Data(contentsOf: legacyPlist)
                let info = try decoder.decode(UncorkedEngineVersion.self, from: data)
                return info.version
            } catch {
                return nil
            }
        }
    }
}

struct UncorkedEngineVersion: Codable {
    var version: SemanticVersion = SemanticVersion(1, 0, 0)
}
