//
//  InlineSettingsView.swift
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
import Sparkle
import CrosswireKit
import AppKit

/// Full-bleed inline settings view shown when `AppRoute == .settings`. Slides
/// in over the library view; Done returns. Replaces the prior standalone
/// SwiftUI `Settings` scene (separate window). Battle.net pattern: left
/// sidebar with section nav, right content pane, version chip bottom-left,
/// Done button bottom-right.
///
/// Content stays largely the same as the prior `SettingsView` in this
/// commit — the per-section content polish (Section 3 of the brief) is a
/// follow-up commit that re-labels toggles, hides container paths,
/// rebuilds About, etc. This commit is purely the structural conversion.
struct InlineSettingsView: View {
    let updater: SPUUpdater?
    var onDone: () -> Void

    // Optional to satisfy `List(selection:)` single-selection binding. nil is
    // treated as `.general` when resolving content.
    @State private var selectedSection: SettingsSection? = .general

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general = "General"
        case updates = "Updates"
        case privacy = "Privacy"
        case about = "About"
        case advanced = "Advanced"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .updates: return "arrow.triangle.2.circlepath"
            case .privacy: return "lock.shield"
            case .about: return "info.circle"
            case .advanced: return "wrench.adjustable"
            }
        }
    }

    init(updater: SPUUpdater? = nil, onDone: @escaping () -> Void) {
        self.updater = updater
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().opacity(0.3)
            HStack(spacing: 0) {
                sidebar
                Divider().opacity(0.3)
                content
            }
            Divider().opacity(0.3)
            footer
        }
        // Transient overlay → material blur over the library shell, per the
        // materials-vs-branded-hex rule.
        .background(.regularMaterial)
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack {
            Text("Settings")
                .font(CrosswireTheme.Typography.title)
                .foregroundStyle(CrosswireTheme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    // MARK: - Sidebar

    /// Native sidebar `List` — inherits sidebar material + vibrancy, free
    /// keyboard navigation, resize and accessibility. The system renders the
    /// selection highlight (the project accent is Crosswire blue, so it's
    /// on-brand); we overlay our 3pt blue left-edge accent bar on the selected
    /// row for brand continuity. No custom selection background.
    private var sidebar: some View {
        List(selection: $selectedSection) {
            // `id: \.self` so each row's selection identity is the
            // `SettingsSection` value itself, matching the `SettingsSection?`
            // binding. Relying on `Identifiable.id` (a String here) would make
            // the selection type mismatch and silently never update.
            ForEach(SettingsSection.allCases, id: \.self) { section in
                sidebarRow(section: section)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .frame(width: 200)
    }

    @ViewBuilder
    private func sidebarRow(section: SettingsSection) -> some View {
        let isSelected = selectedSection == section
        HStack(spacing: 10) {
            // Battle.net signature: blue left-edge accent bar on the selected
            // row, layered over the system selection highlight.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(isSelected ? CrosswireTheme.accent : Color.clear)
                .frame(width: 3, height: 18)
            Image(systemName: section.icon)
                .font(.system(size: 13, weight: .regular))
            Text(section.rawValue)
                .font(CrosswireTheme.Typography.body)
        }
    }

    // MARK: - Content pane

    @ViewBuilder
    private var content: some View {
        ScrollView {
            Group {
                switch selectedSection ?? .general {
                case .general:  generalSection
                case .updates:  updatesSection
                case .privacy:  privacySection
                case .about:    aboutSection
                case .advanced: advancedSection
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader("General")
            // Keep this content as-is for Section 1 (structural commit).
            // Section 3 of the brief rewrites these labels + adds the
            // "Show in Finder" action for App Data Location.
            existingGeneralToggle
        }
    }

    @ViewBuilder
    private var existingGeneralToggle: some View {
        // Defer to the original SettingsView's General toggle by reference
        // so behaviour matches today exactly. Content cleanup is Section 3.
        SettingsGeneralGroup()
    }

    @ViewBuilder
    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader("Updates")
            SettingsUpdatesGroup(updater: updater)
        }
    }

    @ViewBuilder
    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader("Privacy")
            Text(
                "Crash reporting and other privacy controls will live here in a "
                + "future release. None of your activity is shared today."
            )
            .font(CrosswireTheme.Typography.body)
            .foregroundStyle(CrosswireTheme.textSecondary)
            .frame(maxWidth: 420, alignment: .leading)
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader("About")
            SettingsAboutGroup()
        }
    }

    @ViewBuilder
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader("Advanced")
            Text(
                "Power-user controls coming soon. Per-app advanced settings "
                + "live in each app's detail view — click an app in your library."
            )
            .font(CrosswireTheme.Typography.body)
            .foregroundStyle(CrosswireTheme.textSecondary)
            .frame(maxWidth: 420, alignment: .leading)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(CrosswireTheme.textPrimary)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(versionString)
                .font(CrosswireTheme.Typography.entryMeta)
                .foregroundStyle(CrosswireTheme.textTertiary)
                .textSelection(.enabled)
            Spacer()
            Button("Done") { onDone() }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .foregroundStyle(CrosswireTheme.textOnAccent)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(CrosswireTheme.accent)
                )
                .font(CrosswireTheme.Typography.buttonPrimary)
                // Esc dismisses. Return is intentionally NOT bound — the
                // sidebar List below already owns Return for navigating
                // sections, and `.defaultAction` would let the List
                // intercept the Done shortcut first.
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "v\(short)" : "v\(short) (\(build))"
    }
}

// MARK: - Group views (existing-behavior wrappers for Section 1)

/// Wrapped copy of the original General toggles. Section 3 will replace
/// this with cleaned-up content (relabelled defaults path with Show in
/// Finder, theme-tinted toggle). Kept as a small wrapper so this commit is
/// purely structural and the diff stays reviewable.
struct SettingsGeneralGroup: View {
    @AppStorage("killOnTerminate") var killOnTerminate = true
    @AppStorage("defaultBottleLocation") var defaultBottleLocation = BottleData.defaultBottleDir

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Quit running apps when Crosswire quits", isOn: $killOnTerminate)
                .tint(CrosswireTheme.accent)
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textPrimary)
            VStack(alignment: .leading, spacing: 6) {
                Text("Default install location")
                    .font(CrosswireTheme.Typography.body)
                    .foregroundStyle(CrosswireTheme.textPrimary)
                HStack(spacing: 8) {
                    Text(defaultBottleLocation.prettyPath())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(CrosswireTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Change…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = false
                        panel.canCreateDirectories = true
                        panel.directoryURL = BottleData.containerDir
                        panel.begin { result in
                            if result == .OK, let url = panel.urls.first {
                                defaultBottleLocation = url
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(CrosswireTheme.surface)
                )
            }
        }
        .frame(maxWidth: 480, alignment: .leading)
    }
}

/// Wrapped copy of the Updates section. Section 3 will fix the duplicate-
/// label bug (both toggles read as "Crosswire updates" in the prior
/// localized strings) and relabel correctly.
struct SettingsUpdatesGroup: View {
    @AppStorage("SUEnableAutomaticChecks") var crosswireUpdate = true
    @AppStorage("checkEngineUpdates") var checkEngineUpdates = true
    let updater: SPUUpdater?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Automatically check for Crosswire app updates", isOn: $crosswireUpdate)
                .tint(CrosswireTheme.accent)
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textPrimary)
            Toggle("Automatically check for Engine updates", isOn: $checkEngineUpdates)
                .tint(CrosswireTheme.accent)
                .font(CrosswireTheme.Typography.body)
                .foregroundStyle(CrosswireTheme.textPrimary)
            if let updater {
                HStack {
                    Text("Check now")
                        .font(CrosswireTheme.Typography.body)
                        .foregroundStyle(CrosswireTheme.textPrimary)
                    Spacer()
                    SparkleView(updater: updater)
                }
            }
        }
        .frame(maxWidth: 480, alignment: .leading)
    }
}

/// Wrapped About panel — kept simple for Section 1; Section 3 adds the
/// icon, Crosswire wordmark line, engine line, and links.
struct SettingsAboutGroup: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Crosswire")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CrosswireTheme.textPrimary)
                    Text(appVersionString)
                        .font(CrosswireTheme.Typography.body)
                        .foregroundStyle(CrosswireTheme.textSecondary)
                    Text("Engine \(engineVersionString)")
                        .font(CrosswireTheme.Typography.entryMeta)
                        .foregroundStyle(CrosswireTheme.textTertiary)
                }
                Spacer()
            }
        }
        .frame(maxWidth: 480, alignment: .leading)
    }

    private var appVersionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "Version \(short)" : "Version \(short) (\(build))"
    }

    private var engineVersionString: String {
        guard let version = CrosswireEngine.engineVersion() else { return "not installed" }
        return "\(version.major).\(version.minor).\(version.patch)"
    }
}
