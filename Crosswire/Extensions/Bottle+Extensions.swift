//
//  Bottle+Extensions.swift
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
import AppKit
import CrosswireKit
import os.log

extension Bottle {
    func openCDrive() {
        NSWorkspace.shared.open(url.appending(path: "drive_c"))
    }

    func openTerminal() {
        let crosswireCmdURL = Bundle.main.url(forResource: "CrosswireCmd", withExtension: nil)
        if let crosswireCmdURL = crosswireCmdURL {
            let crosswireCmd = crosswireCmdURL.path(percentEncoded: false)
            let cmd = "eval \\\"$(\\\"\(crosswireCmd)\\\" shellenv \\\"\(settings.name)\\\")\\\""

            let script = """
            tell application "Terminal"
            activate
            do script "\(cmd)"
            end tell
            """

            Task(priority: .userInitiated) {
                var error: NSDictionary?
                guard let appleScript = NSAppleScript(source: script) else { return }
                appleScript.executeAndReturnError(&error)

                if let error = error {
                    Logger.wineKit.error("Failed to run terminal script \(error)")
                    guard let description = error["NSAppleScriptErrorMessage"] as? String else { return }
                    self.showRunError(message: String(describing: description))
                }
            }
        }
    }

    @discardableResult
    func getStartMenuPrograms() -> [Program] {
        let globalStartMenu = url
            .appending(path: "drive_c")
            .appending(path: "ProgramData")
            .appending(path: "Microsoft")
            .appending(path: "Windows")
            .appending(path: "Start Menu")

        let userStartMenu = url
            .appending(path: "drive_c")
            .appending(path: "users")
            .appending(path: "crossover")
            .appending(path: "AppData")
            .appending(path: "Roaming")
            .appending(path: "Microsoft")
            .appending(path: "Windows")
            .appending(path: "Start Menu")

        var startMenuPrograms: [Program] = []
        var linkURLs: [URL] = []
        let globalEnumerator = FileManager.default.enumerator(at: globalStartMenu,
                                                              includingPropertiesForKeys: [.isRegularFileKey],
                                                              options: [.skipsHiddenFiles])
        while let url = globalEnumerator?.nextObject() as? URL {
            if url.pathExtension == "lnk" {
                linkURLs.append(url)
            }
        }

        let userEnumerator = FileManager.default.enumerator(at: userStartMenu,
                                                            includingPropertiesForKeys: [.isRegularFileKey],
                                                            options: [.skipsHiddenFiles])
        while let url = userEnumerator?.nextObject() as? URL {
            if url.pathExtension == "lnk" {
                linkURLs.append(url)
            }
        }

        linkURLs.sort(by: { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() })

        for link in linkURLs {
            do {
                if let program = ShellLinkHeader.getProgram(url: link,
                                                            handle: try FileHandle(forReadingFrom: link),
                                                            bottle: self) {
                    if !startMenuPrograms.contains(where: { $0.url == program.url }) {
                        startMenuPrograms.append(program)
                        try FileManager.default.removeItem(at: link)
                    }
                }
            } catch {
                print(error)
            }
        }

        return startMenuPrograms
    }

    func updateInstalledPrograms() {
        let driveC = url.appending(path: "drive_c")
        var programs: [Program] = []
        var foundURLS: Set<URL> = []

        for folderName in ["Program Files", "Program Files (x86)"] {
            let folderURL = driveC.appending(path: folderName)
            let enumerator = FileManager.default.enumerator(
                at: folderURL, includingPropertiesForKeys: [.isExecutableKey], options: [.skipsHiddenFiles]
            )

            while let url = enumerator?.nextObject() as? URL {
                guard !url.hasDirectoryPath && url.pathExtension == "exe" else { continue }
                guard !settings.blocklist.contains(url) else { continue }
                foundURLS.insert(url)
                programs.append(Program(url: url, bottle: self))
            }
        }

        // Add missing programs from pins
        for pin in settings.pins {
            guard let url = pin.url else { continue }
            guard !foundURLS.contains(url) else { continue }
            programs.append(Program(url: url, bottle: self))
        }

        self.programs = programs.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// A user-facing entry the installer registered with Windows. Display
    /// name comes from the Start Menu .lnk filename; URL is the .lnk's
    /// target.
    struct DetectedAppEntry {
        let displayName: String
        let url: URL
    }

    /// Non-destructive Start Menu scan. Returns entries with their display
    /// names, filtered to exclude obvious noise (uninstallers, updaters,
    /// help/website shortcuts, anything pointing into the Windows
    /// directory). Unlike `getStartMenuPrograms()` this does not delete the
    /// .lnk files, so it can run repeatedly.
    func scanStartMenuEntries() -> [DetectedAppEntry] {
        let startMenus = [
            url.appending(path: "drive_c/ProgramData/Microsoft/Windows/Start Menu"),
            url.appending(path: "drive_c/users/crossover/AppData/Roaming/Microsoft/Windows/Start Menu")
        ]

        var linkURLs: [URL] = []
        for root in startMenus {
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            while let candidate = enumerator?.nextObject() as? URL {
                if candidate.pathExtension.lowercased() == "lnk" {
                    linkURLs.append(candidate)
                }
            }
        }

        let windowsDir = url.appending(path: "drive_c/windows").path
        var seenTargets: Set<URL> = []
        var entries: [DetectedAppEntry] = []

        for link in linkURLs.sorted(by: { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }) {
            let displayName = link.deletingPathExtension().lastPathComponent
            if Bottle.isNoiseEntryName(displayName) { continue }
            guard let handle = try? FileHandle(forReadingFrom: link) else { continue }
            defer { try? handle.close() }
            guard let program = ShellLinkHeader.getProgram(url: link, handle: handle, bottle: self) else { continue }
            let target = program.url
            if seenTargets.contains(target) { continue }
            if target.path.hasPrefix(windowsDir) { continue }
            if Bottle.isNoiseEntryName(target.deletingPathExtension().lastPathComponent) { continue }
            seenTargets.insert(target)
            entries.append(DetectedAppEntry(displayName: displayName, url: target))
        }

        return entries
    }

    private static func isNoiseEntryName(_ name: String) -> Bool {
        let lower = name.lowercased()
        let patterns = [
            "uninstall", "unins000", "unins001",
            "setup", "installer",
            "update", "updater", "gup",
            "readme", "read me", "help", "user manual", "manual",
            "website", "on the web", "homepage",
            "change log", "changelog", "release notes",
            "register", "activation",
            "crash", "report",
            "vc_redist", "vcredist", "dxsetup", "directx",
            "winetricks"
        ]
        return patterns.contains { lower.contains($0) }
    }

    /// Run after an install completes. Picks the app's display name and
    /// primary launcher from Start Menu entries (or falls back to a
    /// filtered Program Files sweep when the installer left no shortcuts).
    /// Persists both on the bottle settings.
    func finalizeAppIdentity() {
        let startMenu = scanStartMenuEntries()
        if !startMenu.isEmpty {
            settings.appDisplayName = startMenu[0].displayName
            settings.userVisibleProgramURLs = startMenu.map(\.url)
            if settings.primaryProgramURL == nil
                || !startMenu.contains(where: { $0.url == settings.primaryProgramURL }) {
                settings.primaryProgramURL = startMenu[0].url
            }
            updateInstalledPrograms()
            return
        }

        // No Start Menu entries. Fall back to filtering Program Files,
        // skipping uninstallers/updaters/etc. Used for installers that
        // never created shortcuts and for portable .exes.
        updateInstalledPrograms()
        let visible = programs
            .map(\.url)
            .filter { !Bottle.isNoiseEntryName($0.deletingPathExtension().lastPathComponent) }

        guard !visible.isEmpty else {
            settings.userVisibleProgramURLs = []
            return
        }

        settings.userVisibleProgramURLs = visible
        let primaryStillVisible = settings.primaryProgramURL.map { visible.contains($0) } ?? false
        if !primaryStillVisible {
            settings.primaryProgramURL = visible[0]
        }
    }

    /// Programs the user should see in the main UI. Built from the
    /// detected user-visible URLs when available, otherwise the full
    /// program list (legacy bottles or fresh installs that have not yet
    /// completed detection).
    var userVisiblePrograms: [Program] {
        guard let visible = settings.userVisibleProgramURLs else { return programs }
        return programs.filter { visible.contains($0.url) }
    }

    /// Name shown in the main app list. Prefer the app's own identity over
    /// the installer's filename.
    var displayName: String {
        settings.appDisplayName ?? settings.name
    }

    @MainActor
    func move(destination: URL) {
        do {
            if let bottle = BottleVM.shared.bottles.first(where: { $0.url == url }) {
                bottle.inFlight = true
                for index in 0..<bottle.settings.pins.count {
                    let pin = bottle.settings.pins[index]
                    if let url = pin.url {
                        bottle.settings.pins[index].url = url.updateParentBottle(old: url,
                                                                                 new: destination)
                    }
                }

                for index in 0..<bottle.settings.blocklist.count {
                    let blockedUrl = bottle.settings.blocklist[index]
                    bottle.settings.blocklist[index] = blockedUrl.updateParentBottle(old: url,
                                                                                     new: destination)
                }
            }
            try FileManager.default.moveItem(at: url, to: destination)
            if let path = BottleVM.shared.bottlesList.paths.firstIndex(of: url) {
                BottleVM.shared.bottlesList.paths[path] = destination
            }
            BottleVM.shared.loadBottles()
        } catch {
            print("Failed to move bottle")
        }
    }

    func exportAsArchive(destination: URL) {
        do {
            try Tar.tar(folder: url, toURL: destination)
        } catch {
            print("Failed to export bottle")
        }
    }

    @MainActor
    func remove(delete: Bool) {
        do {
            if let bottle = BottleVM.shared.bottles.first(where: { $0.url == url }) {
                bottle.inFlight = true
            }

            if delete {
                try FileManager.default.removeItem(at: url)
            }

            if let path = BottleVM.shared.bottlesList.paths.firstIndex(of: url) {
                BottleVM.shared.bottlesList.paths.remove(at: path)
            }
            BottleVM.shared.loadBottles()
        } catch {
            print("Failed to remove bottle")
        }
    }

    @MainActor
    func rename(newName: String) {
        settings.name = newName
    }

    private func showRunError(message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "alert.message")
        alert.informativeText = String(localized: "alert.info")
        + " \(self.url.lastPathComponent): "
        + message
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "button.ok"))
        alert.runModal()
    }
}
