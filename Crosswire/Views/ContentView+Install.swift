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
            return
        }

        provisioningMessage = "Running installer..."
        NSApp.miniaturizeAll(nil)
        do {
            try await Wine.runProgram(at: pickedURL, bottle: bottle)
        } catch {
            print("Failed to run installer: \(error)")
        }
        bottle.updateInstalledPrograms()
        provisioningMessage = nil
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

        if programs.count == 1 {
            run(program: programs[0], bottle: bottle)
        } else {
            // Multiple programs and no primary chosen yet — open the
            // settings sheet so the user can pick one explicitly.
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
