/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import Sparkle

struct CheckForUpdatesView: View {
    // Preserve the shared upstream call sites while removing their update action.
    init(updater: SPUUpdater) {}

    var body: some View {
        Text("通过完整 DMG 升级")
            .help("退出当前应用后，用新 DMG 替换整个 App；菜单栏组件随整包一起升级。")
    }
}

struct UpdaterSettingsView: View {
    init(updater: SPUUpdater) {}

    var body: some View {
        Section {
            Text("此版本通过完整 DMG 手动升级。退出当前应用后，替换整个 App，菜单栏组件会一起更新。")
                .foregroundStyle(.secondary)
        } header: {
            Text("Software updates")
        }
    }
}
