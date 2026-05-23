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

public class UncorkedEngine {
    /// ~/Library/Application Support/Uncorked
    public static let applicationFolder = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
    )[0].appending(path: Bundle.uncorkedBundleIdentifier)

    /// ~/Library/Application Support/Uncorked/Libraries
    public static let libraryFolder = applicationFolder.appending(path: "Libraries")

    /// ~/Library/Application Support/Uncorked/Libraries/Wine/bin
    public static let binFolder: URL = libraryFolder
        .appending(path: "Wine")
        .appending(path: "bin")

    // MARK: - State

    public static func isEnginePresent() -> Bool {
        engineVersion() != nil
    }

    public static func engineVersion() -> SemanticVersion? {
        if let v = readVersionPlist(named: "UncorkedEngineVersion") { return v }
        // Fallback for users upgrading from pre-rename installs.
        return readVersionPlist(named: "UncorkedWineVersion")
    }

    private static func readVersionPlist(named name: String) -> SemanticVersion? {
        let url = libraryFolder.appending(path: name).appendingPathExtension("plist")
        guard let data = try? Data(contentsOf: url),
              let info = try? PropertyListDecoder().decode(UncorkedEngineVersion.self, from: data)
        else { return nil }
        return info.version
    }

    // MARK: - Phased install API (used by EngineSetupView)

    /// Fetches the signed manifest from data.grubwire.io and verifies its signature.
    public static func fetchManifest() async throws -> EngineManifest {
        try await EngineManifestClient.fetch()
    }

    /// Downloads the archive for `manifest`, streaming bytes to a temp file.
    /// `progress` is called with (bytesWritten, totalExpected); totalExpected may be -1 if unknown.
    public static func downloadArchive(
        manifest: EngineManifest,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        guard let url = URL(string: manifest.url) else { throw URLError(.badURL) }
        let (byteStream, response) = try await URLSession.shared.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let expected = http.expectedContentLength

        let dest = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString + ".tar.xz")
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let handle = try FileHandle(forWritingTo: dest)

        var buf = Data(capacity: 65536)
        var written: Int64 = 0
        for try await byte in byteStream {
            buf.append(byte)
            if buf.count >= 65536 {
                try handle.write(contentsOf: buf)
                written += Int64(buf.count)
                buf.removeAll(keepingCapacity: true)
                progress(written, expected)
            }
        }
        if !buf.isEmpty {
            try handle.write(contentsOf: buf)
            written += Int64(buf.count)
            progress(written, expected)
        }
        try handle.close()
        return dest
    }

    /// Verifies the archive SHA-256 against the manifest, then extracts and installs.
    public static func verifyAndInstall(archive: URL, manifest: EngineManifest) async throws {
        defer { try? FileManager.default.removeItem(at: archive) }
        try EngineManifestClient.verifyArchive(at: archive, against: manifest)
        let version = parseVersion(manifest.version)
        try await extract(archive: archive, version: version)
    }

    // MARK: - Extraction

    private static func extract(archive: URL, version: SemanticVersion) async throws {
        try FileManager.default.createDirectory(at: applicationFolder, withIntermediateDirectories: true)

        let tempDir = applicationFolder.appending(path: "_extract_tmp")
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        try Tar.untar(tarBall: archive, toURL: tempDir)

        let wineRoot = try findWineRoot(in: tempDir)
        try clearQuarantine(at: wineRoot)

        let dest = libraryFolder.appending(path: "Wine")
        try FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: wineRoot, to: dest)
        try? FileManager.default.removeItem(at: tempDir)

        try writeVersionPlist(version)
    }

    private static func findWineRoot(in dir: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        )
        if let match = contents.first(where: {
            FileManager.default.fileExists(atPath: $0.appending(path: "bin/wine64").path)
            || FileManager.default.fileExists(atPath: $0.appending(path: "bin/wine").path)
        }) { return match }
        guard let first = contents.first else { throw CocoaError(.fileNoSuchFile) }
        return first
    }

    private static func clearQuarantine(at url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", url.path]
        try process.run()
        process.waitUntilExit()
    }

    private static func writeVersionPlist(_ version: SemanticVersion) throws {
        let url = libraryFolder
            .appending(path: "UncorkedEngineVersion")
            .appendingPathExtension("plist")
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(UncorkedEngineVersion(version: version))
        try data.write(to: url)
    }

    // MARK: - Uninstall

    public static func uninstall() {
        try? FileManager.default.removeItem(at: libraryFolder)
    }

    // MARK: - Update check

    /// Returns whether a newer engine is available and the remote version.
    public static func shouldUpdateEngine() async -> (Bool, SemanticVersion) {
        guard let local = engineVersion() else { return (false, SemanticVersion(0, 0, 0)) }
        guard let manifest = try? await EngineManifestClient.fetch() else {
            return (false, SemanticVersion(0, 0, 0))
        }
        let remote = parseVersion(manifest.version)
        return local < remote ? (true, remote) : (false, remote)
    }

    // MARK: - Migration cleanup

    /// Deletes a stale engine left in Application Support by older builds.
    /// Preserves all bottles and wineprefixes. Safe to call on every launch.
    public static func removeLegacyEngineIfNeeded() {
        let flagKey = "uncorkedLegacyEngineRemoved"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        UserDefaults.standard.set(true, forKey: flagKey)
        // The legacy engine lives at Libraries/Wine but has no version plist next to it.
        // The new managed engine always writes UncorkedEngineVersion.plist, so absence of
        // that file is the reliable signal that this is a stale pre-managed install.
        let stale = libraryFolder.appending(path: "Wine")
        let plist = libraryFolder
            .appending(path: "UncorkedEngineVersion")
            .appendingPathExtension("plist")
        if FileManager.default.fileExists(atPath: stale.path)
            && !FileManager.default.fileExists(atPath: plist.path)
        {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    // MARK: - Helpers

    static func parseVersion(_ tag: String) -> SemanticVersion {
        let parts = tag.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }
        let major = parts.first.flatMap { Int($0) } ?? 0
        let minor = parts.dropFirst().first.flatMap { Int($0) } ?? 0
        let patch = parts.dropFirst(2).first.flatMap { Int($0) } ?? 0
        return SemanticVersion(major, minor, patch)
    }
}

struct UncorkedEngineVersion: Codable {
    var version: SemanticVersion = SemanticVersion(1, 0, 0)
}
