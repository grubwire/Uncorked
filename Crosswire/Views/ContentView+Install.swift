//
//  ContentView+Install.swift
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
import AppKit
import UniformTypeIdentifiers
import CrosswireKit

extension ContentView {
    func installWindowsApp() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType.exe,
            UTType(exportedAs: "com.microsoft.msi-installer"),
            UTType(exportedAs: "com.microsoft.bat")
        ]
        panel.begin { result in
            guard result == .OK, let pickedURL = panel.urls.first else { return }
            Task { @MainActor in
                await provisionAndInstall(pickedURL: pickedURL)
            }
        }
    }

    @MainActor
    func provisionAndInstall(pickedURL: URL) async {
        let bottleName = pickedURL.deletingPathExtension().lastPathComponent
        let defaultLocation = UserDefaults.standard.url(forKey: "defaultBottleLocation")
            ?? BottleData.defaultBottleDir

        provisioningMessage = "Setting up..."
        let newBottleURL = bottleVM.createNewBottle(
            bottleName: bottleName,
            winVersion: .win10,
            bottleURL: defaultLocation
        )

        let bottle = await waitForBottle(url: newBottleURL)
        guard let bottle else {
            provisioningMessage = nil
            showInstallAlert(
                title: "Could not set up \(bottleName)",
                body: "Crosswire was unable to prepare a new environment for this app. "
                    + "See the latest run log for details: ~/Library/Logs/app.Crosswire.Crosswire/."
            )
            return
        }

        provisioningMessage = "Running installer..."
        NSApp.miniaturizeAll(nil)
        var installerError: Error?
        do {
            try await Wine.runProgram(at: pickedURL, bottle: bottle)
        } catch {
            installerError = error
            print("Failed to run installer: \(error)")
        }
        bottle.finalizeAppIdentity()

        if let installerError {
            provisioningMessage = nil
            showInstallAlert(
                title: "Installer could not start",
                body: "\(installerError.localizedDescription)\n\n"
                    + "The bottle was created but the installer never ran. "
                    + "See the latest log at ~/Library/Logs/app.Crosswire.Crosswire/."
            )
            return
        }

        // If the install scan found nothing AND the picked file was a
        // portable .exe (no .msi, no .bat), treat the .exe itself as the
        // app — copy it into the bottle so Crosswire's program scan picks
        // it up and the Run button works. Without this, self-contained
        // tools like the SWG Legends launcher (10MB Java launcher with
        // bundled JRE) trigger a "no apps detected" warning even though
        // the .exe IS the app the user wanted to run.
        if bottle.userVisiblePrograms.isEmpty,
           pickedURL.pathExtension.lowercased() == "exe",
           adoptPortableExe(pickedURL, into: bottle) {
            provisioningMessage = nil
            return
        }
        provisioningMessage = nil

        if bottle.userVisiblePrograms.isEmpty {
            showInstallAlert(
                title: "Installer finished but no apps were detected",
                body: "The installer ran, but Crosswire could not find anything to launch. "
                    + "Check the latest run log for details: ~/Library/Logs/app.Crosswire.Crosswire/. "
                    + "You can delete the app from its settings panel and try again."
            )
        }
    }

    /// Copy a portable .exe the user picked into the bottle's
    /// `Program Files (x86)/<stem>/` so subsequent program scans and the
    /// Run button can find it. Sets primaryProgramURL + userVisible to
    /// the in-bottle path. Returns true on success.
    private func adoptPortableExe(_ source: URL, into bottle: Bottle) -> Bool {
        let stem = source.deletingPathExtension().lastPathComponent
        let targetDir = bottle.url
            .appending(path: "drive_c")
            .appending(path: "Program Files (x86)")
            .appending(path: stem)
        let targetURL = targetDir.appending(path: source.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: targetURL.path(percentEncoded: false)) {
                try FileManager.default.copyItem(at: source, to: targetURL)
            }
        } catch {
            print("Failed to adopt portable exe \(source.lastPathComponent): \(error)")
            return false
        }
        bottle.updateInstalledPrograms()
        bottle.settings.primaryProgramURL = targetURL
        bottle.settings.userVisibleProgramURLs = [targetURL]
        return true
    }

    private func showInstallAlert(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @MainActor
    func waitForBottle(url: URL) async -> Bottle? {
        // createNewBottle spawns an inner Task; poll the published list until
        // the bottle flips out of inFlight. ~30s ceiling.
        for _ in 0..<300 {
            if let bottle = bottleVM.bottles.first(where: { $0.url == url }), !bottle.inFlight {
                return bottle
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return bottleVM.bottles.first(where: { $0.url == url })
    }

    func runPrimary(for bottle: Bottle) {
        guard bottle.isAvailable else { return }
        bottle.updateInstalledPrograms()
        let programs = bottle.programs
        guard !programs.isEmpty else { return }

        if let primaryURL = bottle.settings.primaryProgramURL,
           let primary = programs.first(where: { $0.url == primaryURL }) {
            run(program: primary, bottle: bottle)
            return
        }

        let visible = bottle.userVisiblePrograms
        if visible.count == 1 {
            run(program: visible[0], bottle: bottle)
        } else if visible.count > 1 {
            run(program: visible[0], bottle: bottle)
        } else if programs.count == 1 {
            run(program: programs[0], bottle: bottle)
        } else {
            // No detection has run and no primary is set; open settings
            // so the user can pick one explicitly.
            settingsBottle = bottle
        }
    }

    func run(program: Program, bottle: Bottle) {
        NSApp.miniaturizeAll(nil)
        Task(priority: .userInitiated) {
            do {
                try await Wine.runProgram(at: program.url, bottle: bottle)
            } catch {
                print("Failed to run program: \(error)")
            }
        }
    }
}
