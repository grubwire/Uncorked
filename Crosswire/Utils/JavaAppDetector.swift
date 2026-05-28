//
//  JavaAppDetector.swift
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

import Foundation
import CrosswireKit

/// File-system heuristic for detecting that an .exe ships its own JRE
/// (a "self-contained Java" launcher). These launchers — SWG Legends is
/// the case that burned us — render with JavaFX/Prism, which crashes or
/// sliver-renders under Wine until `_JAVA_OPTIONS` flips Prism to the
/// j2d (software) pipeline and the JVM into interpreted mode.
///
/// Pure functions, no side effects beyond reading the file system. Kept
/// separate from `RuntimeDetector` (which inspects PE imports for Win32
/// dynamic dependencies like VC++/dotnet/d3dx): the two are orthogonal —
/// PE imports don't reveal a bundled JRE.
enum JavaAppDetector {
    /// JVM/JavaFX env vars that paper over the Prism rendering issues
    /// hit by bundled-JRE launchers under Wine.
    ///
    /// - `-Dprism.order=j2d` forces the JavaFX Prism pipeline to the
    ///   software (Java2D) renderer instead of d3d/es2, which Wine's
    ///   graphics stack doesn't satisfy for these launchers.
    /// - `-Xint` runs the JVM in pure-interpreted mode, sidestepping
    ///   JIT codegen paths that have repeatedly tripped Wine.
    static let recommendedJavaOptions = "-Dprism.order=j2d -Xint"

    /// Returns true if the directory tree rooted at (or beside) `exeURL`
    /// looks like it ships its own JRE.
    ///
    /// Checks, in order, beside the .exe:
    ///   - `lib/jre/bin/javaw.exe`   (common Oracle / Liberica layout)
    ///   - `lib/jre/bin/java.exe`
    ///   - `lib/jre/release`         (text file, must contain `JAVA_VERSION=`)
    ///   - `app/runtime/bin/javaw.exe` (newer jpackage / launcher layout)
    ///
    /// Any single hit is sufficient — these layouts are stable enough
    /// across vendors that one match is a confident signal, not a coin
    /// flip.
    static func isSelfContainedJavaApp(at exeURL: URL) -> Bool {
        let parent = exeURL.deletingLastPathComponent()
        let fileMarkers = [
            parent.appending(path: "lib/jre/bin/javaw.exe"),
            parent.appending(path: "lib/jre/bin/java.exe"),
            parent.appending(path: "app/runtime/bin/javaw.exe")
        ]
        for marker in fileMarkers where FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)) {
            return true
        }
        let releaseURL = parent.appending(path: "lib/jre/release")
        if FileManager.default.fileExists(atPath: releaseURL.path(percentEncoded: false)),
           let contents = try? String(contentsOf: releaseURL, encoding: .utf8),
           contents.contains("JAVA_VERSION=") {
            return true
        }
        return false
    }

    /// If `exeURL` looks like a self-contained Java launcher AND no
    /// per-program plist exists yet, write a default plist seeded with
    /// `_JAVA_OPTIONS`. Existing plists are left alone — the user may
    /// have customized them.
    ///
    /// The plist is written via `ProgramSettings.encode(to:)` (Codable +
    /// `PropertyListEncoder`) rather than a string template, so `locale`
    /// serializes as an empty string (`Locales.auto.rawValue == ""`).
    /// A hand-written `<string>auto</string>` would make
    /// `PropertyListDecoder` throw `dataCorrupted` next launch.
    @discardableResult
    @MainActor
    static func writeDefaultPlistIfNeeded(forExeAt exeURL: URL, in bottle: Bottle) -> Bool {
        guard isSelfContainedJavaApp(at: exeURL) else { return false }

        let settingsDir = bottle.url.appending(path: "Program Settings")
        let plistURL = settingsDir
            .appending(path: exeURL.lastPathComponent)
            .appendingPathExtension("plist")

        // Contract: don't overwrite a user-customized plist.
        if FileManager.default.fileExists(atPath: plistURL.path(percentEncoded: false)) {
            return false
        }

        do {
            try FileManager.default.createDirectory(at: settingsDir, withIntermediateDirectories: true)
            var settings = ProgramSettings()
            settings.locale = .auto                // .auto.rawValue == "" — see doc above.
            settings.environment = ["_JAVA_OPTIONS": recommendedJavaOptions]
            settings.arguments = ""
            try settings.encode(to: plistURL)
            return true
        } catch {
            print("JavaAppDetector: failed to write default plist for \(exeURL.lastPathComponent): \(error)")
            return false
        }
    }
}
