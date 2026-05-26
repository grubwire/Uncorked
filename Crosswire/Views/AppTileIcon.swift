//
//  AppTileIcon.swift
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

/// Stable palette used for the placeholder app tiles. Picked to feel friendly
/// against both light and dark window chrome.
private let appTilePalette: [Color] = [
    Color(red: 0.27, green: 0.45, blue: 0.85),
    Color(red: 0.85, green: 0.35, blue: 0.40),
    Color(red: 0.38, green: 0.65, blue: 0.42),
    Color(red: 0.85, green: 0.55, blue: 0.25),
    Color(red: 0.55, green: 0.40, blue: 0.80),
    Color(red: 0.20, green: 0.60, blue: 0.70),
    Color(red: 0.80, green: 0.45, blue: 0.65),
    Color(red: 0.45, green: 0.50, blue: 0.55)
]

/// Deterministic color for an app/bottle name. Uses a tiny djb2-style hash so
/// the same name always lands on the same palette slot regardless of run.
func colorForProgramName(_ name: String) -> Color {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return appTilePalette[0] }
    var hash: UInt32 = 5381
    for scalar in trimmed.unicodeScalars {
        hash = hash &* 33 &+ scalar.value
    }
    return appTilePalette[Int(hash % UInt32(appTilePalette.count))]
}

/// Up to two uppercase initials drawn from the leading word characters of an
/// app name. Falls back to the first two characters if no word boundary is
/// found.
func initialsForProgramName(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "?" }
    let words = trimmed.split { !$0.isLetter && !$0.isNumber }
    if words.isEmpty {
        return String(trimmed.prefix(2)).uppercased()
    }
    if words.count == 1 {
        return String(words[0].prefix(2)).uppercased()
    }
    let first = words[0].first.map { String($0) } ?? ""
    let second = words[1].first.map { String($0) } ?? ""
    return (first + second).uppercased()
}

/// Square tile with the bottle's color and initials, sized 42x42 by default.
struct AppTileIcon: View {
    let name: String
    var side: CGFloat = 42

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(colorForProgramName(name))
            Text(initialsForProgramName(name))
                .font(.system(size: side * 0.38, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: side, height: side)
    }
}
