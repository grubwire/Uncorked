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
        // Concurrent-install guard. provisionAndInstall is @MainActor and
        // its `await`s suspend the main actor. Two of these in flight at
        // the same time deadlocked the UI on 2026-05-28 when bug #94's
        // wineserver-await held the first install open and the second
        // install was started. provisioningMessage is set synchronously on
        // entry and cleared on exit, so it's a reliable in-flight signal.
        if provisioningMessage != nil {
            showInstallAlert(
                title: "Install already in progress",
                body: "Wait for the current install to finish before starting a new one. "
                    + "You can see its progress in the status row at the bottom of the window."
            )
            return
        }
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
            // Defense in depth: re-check at the actual Task entry in case
            // the user re-opened the panel via a different code path while
            // the previous panel was open.
            Task { @MainActor in
                if provisioningMessage != nil {
                    showInstallAlert(
                        title: "Install already in progress",
                        body: "Wait for the current install to finish."
                    )
                    return
                }
                await provisionAndInstall(pickedURL: pickedURL)
            }
        }
    }

    // swiftlint:disable function_body_length
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

        // Static-analyze the picked exe's PE imports BEFORE running it. If we
        // detect runtimes the bottle doesn't have (vcrun, dotnet, d3dx, etc.),
        // surface a confirmation sheet that installs them via winetricks
        // first. .msi / .bat get skipped because their PE imports don't
        // describe what the installer will run.
        let detected = pickedURL.pathExtension.lowercased() == "exe"
            ? RuntimeDetector.detect(at: pickedURL)
            : []
        if !detected.isEmpty {
            provisioningMessage = nil
            let installed = await presentRuntimesSheet(
                exeName: pickedURL.lastPathComponent, detected: detected, bottle: bottle
            )
            provisioningMessage = "Running \(installed.isEmpty ? "installer" : "installer (runtimes ready)")..."
        } else {
            provisioningMessage = "Running installer..."
        }
        var installerError: Error?
        do {
            // runInstaller uses direct `wine <path>` invocation (not
            // `start /unix`) so this await returns as soon as the
            // installer's own .exe exits, NOT when wineserver releases.
            // Bug #94: with `start /unix` semantics, an installer that
            // ShellExecutes a "Run after install" launcher kept this await
            // open until the user closed the launcher, blocking
            // finalizeAppIdentity + JavaAppDetector from running.
            try await Wine.runInstaller(at: pickedURL, bottle: bottle)
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
           await adoptPortableExe(pickedURL, into: bottle) {
            provisioningMessage = nil
            return
        }

        // After a regular installer run, scan the detected programs for
        // self-contained Java launchers (e.g. JavaFX game launchers that
        // ship their own JRE next to the .exe). For each match with no
        // existing per-program plist, seed one with _JAVA_OPTIONS so the
        // first launch doesn't sliver-render under Prism d3d. Runs
        // before any auto-launch attempt. Orthogonal to RuntimeDetector,
        // which only sees Win32 PE imports.
        for program in bottle.userVisiblePrograms {
            await JavaAppDetector.applyDefaultsIfNeeded(forExeAt: program.url, in: bottle)
        }

        // Clean up anything the installer may have already spawned (notably
        // the "Run <app> after install" Finish-step launcher in Inno Setup
        // and friends). That launcher started BEFORE the auto-features
        // above were applied, so its JVM read empty env vars and the
        // dwrite override wasn't yet in user.reg — net result is a sliver-
        // render or post-Login crash on what looks to the user like the
        // first run of their freshly-installed app. Killing the bottle's
        // wineserver takes the half-configured launcher down so the auto-
        // launch below starts cleanly with all auto-features applied.
        try? Wine.killBottle(bottle: bottle)

        provisioningMessage = nil

        if bottle.userVisiblePrograms.isEmpty {
            showInstallAlert(
                title: "Installer finished but no apps were detected",
                body: "The installer ran, but Crosswire could not find anything to launch. "
                    + "Check the latest run log for details: ~/Library/Logs/app.Crosswire.Crosswire/. "
                    + "You can delete the app from its settings panel and try again."
            )
            return
        }

        // Auto-launch the freshly-installed app. The installer's wizard
        // promised "Run <app> after install" — we just killed THAT launcher
        // because it started before our auto-features applied. Auto-launch
        // here gives the user what they expected (their app opens), but now
        // with the plist's _JAVA_OPTIONS + dwrite=builtin in effect from
        // first paint. Brief settle so wineserver -k from killBottle finishes
        // tearing down before the new launch comes up against a half-dead
        // wineserver.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            runPrimary(for: bottle)
        }
    }
    // swiftlint:enable function_body_length

    /// Present the runtimes-detected sheet and suspend until the user
    /// makes a decision. Returns the verbs that were actually installed
    /// (empty when the user skipped).
    @MainActor
    func presentRuntimesSheet(
        exeName: String, detected: [DetectedRuntime], bottle: Bottle
    ) async -> [String] {
        await withCheckedContinuation { continuation in
            runtimesPrompt = RuntimesPrompt(
                exeName: exeName,
                detected: detected,
                bottle: bottle,
                continuation: continuation
            )
        }
    }

    /// Copy a portable .exe the user picked into the bottle's
    /// `Program Files (x86)/<stem>/` so subsequent program scans and the
    /// Run button can find it. Sets primaryProgramURL + userVisible to
    /// the in-bottle path. Returns true on success.
    private func adoptPortableExe(_ source: URL, into bottle: Bottle) async -> Bool {
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

        // Check the SOURCE dir tree for a bundled JRE — that's where the
        // lib/jre layout lives; we only copy the .exe into the bottle,
        // not the surrounding tree. The plist is written for the
        // in-bottle target path (same basename as source, so the helper
        // keys it correctly off lastPathComponent).
        await JavaAppDetector.applyDefaultsIfNeeded(forExeAt: source, in: bottle)
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
            // No detection has run and no primary is set; open the entry's
            // detail view so the user can pick a primary launcher explicitly
            // (the picker lives under Advanced).
            withAnimation(.easeInOut(duration: 0.2)) {
                route = .entryDetail(bottle.id)
            }
        }
    }

    func run(program: Program, bottle: Bottle) {
        // Single-instance: unless this bottle opts into multiple instances, a
        // Launch on an app that's already running focuses the existing window
        // instead of spawning a duplicate. We only suppress the spawn when we
        // find a live, focusable window — otherwise we fall through and launch,
        // so the guard can never get stuck blocking legitimate launches.
        if !bottle.settings.allowMultipleInstances {
            let liveApps = Wine.runningProcessIDs(for: bottle)
                .compactMap { NSRunningApplication(processIdentifier: $0) }
                .filter { !$0.isTerminated }
            if let existing = liveApps.first(where: { $0.activationPolicy == .regular }) {
                existing.activate(options: [.activateAllWindows])
                return
            }
        }
        Task(priority: .userInitiated) {
            do {
                try await Wine.runProgram(at: program.url, bottle: bottle)
            } catch {
                print("Failed to run program: \(error)")
            }
        }
    }
}
