//
//  ContentView.swift
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
import CrosswireKit
import SemanticVersion
import Sparkle

// swiftlint:disable type_body_length file_length
struct ContentView: View {
    @AppStorage("checkEngineUpdates") var checkEngineUpdates = true
    @EnvironmentObject var bottleVM: BottleVM
    @Binding var showSetup: Bool
    let sparkleUpdater: SPUUpdater?

    @State var bottlesLoaded: Bool = false
    @State var searchText: String = ""
    @State var openedFileURL: URL?
    @State var setupStartingStage: SetupStage?

    /// Top-level navigation. Library is the default; Settings + per-entry
    /// detail are full-bleed inline destinations that slide in over the
    /// library view. See `AppRoute` for the full rationale.
    @State var route: AppRoute = .library

    /// Retained for compatibility with the install flow's existing alerts;
    /// the per-entry settings sheet is no longer driven by this (now it's
    /// navigation via `route = .entryDetail(bottle.id)`).
    @State var settingsBottle: Bottle?
    @State var provisioningMessage: String?
    @State var runtimesPrompt: RuntimesPrompt?

    @FocusState private var searchFocused: Bool

    init(showSetup: Binding<Bool>, sparkleUpdater: SPUUpdater? = nil) {
        self._showSetup = showSetup
        self.sparkleUpdater = sparkleUpdater
    }

    var body: some View {
        ZStack {
            // Library is the always-present base layer. Settings + per-entry
            // detail overlay it with slide-in transitions. Library doesn't
            // animate out — the overlay just covers it.
            libraryRoot

            if route == .settings {
                InlineSettingsView(updater: sparkleUpdater) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        route = .library
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CrosswireTheme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Crosswire")
        .toolbar { crosswireToolbar }
        .sheet(item: $settingsBottle) { bottle in
            // Per-entry settings still uses .sheet for this commit. Section 2
            // of the brief converts it to inline routing via .entryDetail.
            AppSettingsSheet(bottle: bottle, onDelete: {
                settingsBottle = nil
            })
        }
        .sheet(item: $openedFileURL) { url in
            FileOpenView(fileURL: url,
                         currentBottle: nil,
                         bottles: bottleVM.bottles)
        }
        .sheet(item: $runtimesPrompt) { prompt in
            DetectedRuntimesSheet(
                exeName: prompt.exeName,
                detected: prompt.detected,
                bottle: prompt.bottle
            ) { installed in
                prompt.continuation.resume(returning: installed)
                runtimesPrompt = nil
            }
        }
        .sheet(isPresented: $showSetup, onDismiss: { setupStartingStage = nil }, content: {
            SetupView(startingStage: setupStartingStage, showSetup: $showSetup, firstTime: false)
        })
        .overlay {
            if let message = provisioningMessage {
                ProvisioningOverlay(message: message)
            }
        }
        .handlesExternalEvents(preferring: [], allowing: ["*"])
        .onOpenURL { url in
            openedFileURL = url
        }
        .task {
            await onAppearTask()
        }
    }

    // MARK: - Library root (composes header + action row + content)

    /// The library view as a single composed surface. Sits at the base of
    /// the ZStack; the Settings (and per-entry, Section 2) overlays slide
    /// in over it. Extracted as its own var so the body-level ZStack stays
    /// readable.
    private var libraryRoot: some View {
        VStack(spacing: 0) {
            actionRow
            content
        }
    }

    // MARK: - Toolbar (native unified, replaces the old custom header)

    /// Native unified toolbar. Leading: brand icon + chevron menu (Settings /
    /// About / Check for Updates / Quit). The inline window title ("Crosswire")
    /// is set via `.navigationTitle` and renders next to the traffic lights.
    /// Trailing primary-action group: sparkle (What's New, future), bell
    /// (Notifications, future), gear (Settings), and the prominent blue "+"
    /// install button — the primary action, visually distinct from the
    /// placeholder symbols.
    /// App icon redrawn into a genuinely 18pt bitmap for the leading toolbar
    /// menu. Neither `.resizable().frame()` nor setting `.size` on a copy
    /// constrains the render inside a toolbar `Menu` label — SwiftUI keeps the
    /// source's full-size representations and the icon bleeds over the content
    /// below. Redrawing produces an image whose intrinsic size really is 18pt.
    private static let brandToolbarIcon: NSImage = {
        let side: CGFloat = 18
        let source = NSApplication.shared.applicationIconImage ?? NSImage()
        // Block-based redraw: intrinsic size is a true 18pt (fixes the toolbar
        // Menu label keeping the source's full-size reps), and the closure is
        // invoked at the backing scale so it stays crisp on Retina. Drawing
        // into the full rect centers the source content within the bounds.
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
    }()

    @ToolbarContentBuilder
    private var crosswireToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Menu {
                Button("Settings…") {
                    withAnimation(.easeInOut(duration: 0.2)) { route = .settings }
                }
                Button("About Crosswire") { CrosswireApp.openAboutWindow() }
                Button("Check for Updates…") { sparkleUpdater?.checkForUpdates() }
                Divider()
                Button("Quit Crosswire") { NSApp.terminate(nil) }
            } label: {
                Image(nsImage: Self.brandToolbarIcon)
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            .menuIndicator(.visible)
            .help("Crosswire")
            .accessibilityLabel("Crosswire menu")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                // What's New — placeholder, non-functional this pass.
            } label: {
                Image(systemName: "sparkles")
            }
            .help("What’s New")
            .accessibilityLabel("What’s New")

            Button {
                // Notifications — placeholder, non-functional this pass.
            } label: {
                Image(systemName: "bell")
            }
            .help("Notifications")
            .accessibilityLabel("Notifications")

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { route = .settings }
            } label: {
                Image(systemName: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")

            Button(action: installWindowsApp) {
                Label("Install", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(CrosswireTheme.accent)
            .help("Install a Windows game or app")
            .accessibilityLabel("Install a Game or App")
        }
    }

    // MARK: - Action row (search)

    /// Library search. The "Install a Game or App" CTA moved to the toolbar's
    /// trailing primary-action group (Commit 2); this row now just hosts the
    /// search field below the toolbar.
    private var actionRow: some View {
        HStack(spacing: 12) {
            librarySearchField
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    /// Search field with the theme's surface fill and a blue focus ring that
    /// honors the Crosswire accent instead of the user's system accent
    /// (which could be orange and clash with the icon).
    private var librarySearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CrosswireTheme.textTertiary)
            TextField("Search your library…", text: $searchText)
                .textFieldStyle(.plain)
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textPrimary)
                .focused($searchFocused)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CrosswireTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    searchFocused ? CrosswireTheme.accent : CrosswireTheme.surfaceStroke,
                    lineWidth: searchFocused ? 1.5 : 1
                )
        )
        .frame(maxWidth: .infinity)
        .animation(CrosswireTheme.Motion.hover, value: searchFocused)
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if !bottlesLoaded {
            loadingState
        } else if bottleVM.bottles.isEmpty {
            emptyState
        } else if filteredBottles.isEmpty {
            noMatchState
        } else {
            library
        }
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var noMatchState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(CrosswireTheme.textTertiary)
            Text("Nothing in your library matches “\(searchText)”")
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// The library list. Section label sits above the rows so the user
    /// understands what they're looking at — and it gives the surface a
    /// header anchor instead of floating rows on a gradient.
    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Library")
                    .font(CrosswireTheme.Typography.sectionHeader)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(CrosswireTheme.textSecondary)
                Spacer()
                Text("^[\(filteredBottles.count) item](inflect: true)")
                    .font(CrosswireTheme.Typography.entryMeta)
                    .foregroundStyle(CrosswireTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filteredBottles) { bottle in
                        AppRow(
                            bottle: bottle,
                            onPrimaryAction: { runPrimary(for: bottle) },
                            onRun: { runPrimary(for: bottle) },
                            onRunSpecific: { program in
                                run(program: program, bottle: bottle)
                            },
                            onOpenSettings: { settingsBottle = bottle }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .animation(.default, value: bottleVM.bottles)
            .animation(.default, value: searchText)
        }
        // The library is a contained surface (Battle.net favorites-bar
        // pattern): branded hex region over the page gradient, not a material.
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CrosswireTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CrosswireTheme.regionBorder, lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    /// First-launch / empty-library state. Uses the app's own icon (single
    /// source of truth — if the icon changes, so does this view), the
    /// brand tagline, and the same blue CTA that drives the action row.
    private var emptyState: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 128, height: 128)
                .shadow(color: CrosswireTheme.accent.opacity(0.25), radius: 24, x: 0, y: 8)
            VStack(spacing: 8) {
                Text("Your Windows library, on Mac.")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(CrosswireTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Drop a Windows .exe to install your first game or app.")
                    .font(CrosswireTheme.Typography.body)
                    .foregroundStyle(CrosswireTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: installWindowsApp) {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text("Install a Game or App")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(CrosswireTheme.textOnAccent)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(CrosswireTheme.accent)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - Derived

    var filteredBottles: [Bottle] {
        let sorted = bottleVM.bottles.sorted()
        if searchText.isEmpty { return sorted }
        return sorted.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Lifecycle

    @MainActor
    private func onAppearTask() async {
        bottleVM.loadBottles()
        bottlesLoaded = true

        if !CrosswireEngine.isEnginePresent() {
            setupStartingStage = nil
            showSetup = true
            return
        }

        let updateInfo = await CrosswireEngine.shouldUpdateEngine()
        guard checkEngineUpdates, updateInfo.0 else { return }

        let alert = NSAlert()
        alert.messageText = String(localized: "update.engine.title")
        alert.informativeText = String(format: String(localized: "update.engine.description"),
                                       String(CrosswireEngine.engineVersion()
                                              ?? SemanticVersion(0, 0, 0)),
                                       String(updateInfo.1))
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "update.engine.update"))
        alert.addButton(withTitle: String(localized: "button.removeAlert.cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            CrosswireEngine.uninstall()
            setupStartingStage = .engineSetup
            showSetup = true
        }
    }
}

// swiftlint:enable type_body_length

/// Modal overlay shown while a new app is being provisioned.
struct ProvisioningOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                Text(message)
                    .font(CrosswireTheme.Typography.body)
                    .foregroundStyle(CrosswireTheme.textPrimary)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CrosswireTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(CrosswireTheme.surfaceStroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 12)
        }
    }
}

#Preview {
    ContentView(showSetup: .constant(false))
        .environmentObject(BottleVM.shared)
}
