//
//  CrosswireApp.swift
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

import AppKit
import SwiftUI
import Sparkle
import CrosswireKit

@main
struct CrosswireApp: App {
    @State var showSetup: Bool = false
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openURL) var openURL
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true,
                                                         updaterDelegate: nil,
                                                         userDriverDelegate: nil)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(showSetup: $showSetup, updater: updaterController.updater)
                .frame(minWidth: ViewWidth.large, minHeight: 316)
                .environmentObject(BottleVM.shared)
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false

                    Task.detached {
                        await CrosswireApp.deleteOldLogs()
                    }
                    Task.detached {
                        CrosswireEngine.removeLegacyEngineIfNeeded()
                    }
                }
        }
        // Don't ask me how this works, it just does
        .handlesExternalEvents(matching: ["{same path of URL?}"])
        .commands {
            CommandGroup(after: .appInfo) {
                SparkleView(updater: updaterController.updater)
            }
            CommandGroup(before: .systemServices) {
                Divider()
                Button("open.setup") {
                    showSetup = true
                }
                Button("install.cli") {
                    Task {
                        await CrosswireCmd.install()
                    }
                }
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("open.bottle") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = false
                    panel.begin { result in
                        if result == .OK {
                            if let url = panel.urls.first {
                                BottleVM.shared.bottlesList.paths.append(url)
                                BottleVM.shared.loadBottles()
                            }
                        }
                    }
                }
                .keyboardShortcut("I", modifiers: [.command])
            }
            CommandGroup(after: .importExport) {
                Button("open.logs") {
                    CrosswireApp.openLogsFolder()
                }
                .keyboardShortcut("L", modifiers: [.command])
                Button("kill.bottles") {
                    CrosswireApp.killBottles()
                }
                .keyboardShortcut("K", modifiers: [.command, .shift])
                Button("wine.clearShaderCaches") {
                    CrosswireApp.killBottles() // Better not make things more complicated for ourselves
                    CrosswireApp.wipeShaderCaches()
                }
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Crosswire") {
                    openAboutWindow()
                }
            }
            CommandGroup(replacing: .help) {
                Button("help.website") {
                    if let url = URL(string: "https://grubwire.io") {
                        openURL(url)
                    }
                }
                Button("help.wiki") {
                    if let url = URL(string: "https://grubwire.io/crosswire/wiki/") {
                        openURL(url)
                    }
                }
                Button("help.github") {
                    if let url = URL(string: "https://github.com/grubwire/Crosswire") {
                        openURL(url)
                    }
                }
                Divider()
                Button("Diagnostics...") {
                    openDiagnosticsWindow()
                }
            }
        }
        Settings {
            SettingsView()
        }
    }

    // MARK: - Window helpers

    @MainActor private func openAboutWindow() {
        let existing = NSApp.windows.first { $0.title == "About Crosswire" }
        if let existingWindow = existing {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        let view = NSHostingView(rootView: AboutView())
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Crosswire"
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor private func openDiagnosticsWindow() {
        let existing = NSApp.windows.first { $0.title == "Diagnostics" }
        if let existingWindow = existing {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        let view = NSHostingView(rootView: DiagnosticsView())
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Diagnostics"
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor static func killBottles() {
        for bottle in BottleVM.shared.bottles {
            do {
                try Wine.killBottle(bottle: bottle)
            } catch {
                print("Failed to kill bottle: \(error)")
            }
        }
    }

    static func openLogsFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Wine.logsFolder.path)
    }

    static func deleteOldLogs() {
        let pastDate = Date().addingTimeInterval(-7 * 24 * 60 * 60)

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: Wine.logsFolder,
            includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }

        let logs = urls.filter { url in
            url.pathExtension == "log"
        }

        let oldLogs = logs.filter { url in
            do {
                let resourceValues = try url.resourceValues(forKeys: [.creationDateKey])

                return resourceValues.creationDate ?? Date() < pastDate
            } catch {
                return false
            }
        }

        for log in oldLogs {
            do {
                try FileManager.default.removeItem(at: log)
            } catch {
                print("Failed to delete log: \(error)")
            }
        }
    }

    static func wipeShaderCaches() {
        let getconf = Process()
        getconf.executableURL = URL(fileURLWithPath: "/usr/bin/getconf")
        getconf.arguments = ["DARWIN_USER_CACHE_DIR"]
        let pipe = Pipe()
        getconf.standardOutput = pipe
        do {
            try getconf.run()
        } catch {
            return
        }
        getconf.waitUntilExit()
        let getconfOutput = {() -> Data in
            if #available(macOS 10.15, *) {
                do {
                    return try pipe.fileHandleForReading.readToEnd() ?? Data()
                } catch {
                    return Data()
                }
            } else {
                return pipe.fileHandleForReading.readDataToEndOfFile()
            }
        }()
        guard let getconfOutputString = String(data: getconfOutput, encoding: .utf8) else {return}
        let d3dmPath = URL(fileURLWithPath: getconfOutputString.trimmingCharacters(in: .whitespacesAndNewlines))
            .appending(path: "d3dm").path
        do {
            try FileManager.default.removeItem(atPath: d3dmPath)
        } catch {
            return
        }
    }
}
