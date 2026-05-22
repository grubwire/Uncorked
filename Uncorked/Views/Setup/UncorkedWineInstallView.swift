//
//  UncorkedWineInstallView.swift
//  Uncorked
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

import SwiftUI
import UncorkedKit

struct UncorkedWineInstallView: View {
    @State var installing: Bool = true
    @Binding var tarLocation: URL
    @Binding var wineTagName: String
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool

    var body: some View {
        VStack {
            VStack {
                Text("setup.uncorkedwine.install")
                    .font(.title)
                    .fontWeight(.bold)
                Text("setup.uncorkedwine.install.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if installing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 80)
                } else {
                    Image(systemName: "checkmark.circle")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.green)
                }
                Spacer()
            }
            Spacer()
        }
        .frame(width: 400, height: 200)
        .onAppear {
            Task.detached {
                let tag = await MainActor.run { wineTagName }
                let loc = await MainActor.run { tarLocation }
                await UncorkedWineInstaller.install(from: loc, tagName: tag.isEmpty ? nil : tag)
                await MainActor.run {
                    installing = false
                }
                sleep(2)
                await proceed()
            }
        }
    }

    @MainActor
    func proceed() {
        showSetup = false
    }
}
