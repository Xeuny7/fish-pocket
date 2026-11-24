#!/usr/bin/env python3
"""Apply the dsh-go style skin to the whole iOS app before building.

Run by CI from scripts/build-engine.sh. Idempotent; every anchor that cannot be
found aborts the build, so a half-skinned app can never ship silently.

Layers:
  1. writes app/DshIOS/Views/SkinStyle.swift (badge, page surface, modifier)
  2. Theme.swift: page + grouped-list backgrounds use the page surface, and
     settings rows take the card colour (this is the global switch: 39 views
     draw through groupedList(), 5 through pageBackground())
  3. app root, conversation view, remote panel, fish-pocket pages: the few
     places that paint their own background
  4. SettingsView.swift: row icons become tonal symbols
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
V = ROOT / "app" / "DshIOS"

SKIN = V / "Views" / "SkinStyle.swift"
THEME = V / "Views" / "Theme.swift"
SETTINGS = V / "Views" / "SettingsView.swift"
APP = V / "DshIOSApp.swift"
CONV = V / "Views" / "ConversationView.swift"
RECORDS = V / "Views" / "FishPocketRecordsPage.swift"
POCKET = V / "Views" / "FishPocketViews.swift"
PANELS = V / "Remote" / "RemotePanels.swift"

SKIN_SWIFT = r"""// dsh-go 风格皮肤层（由 tooling/skin/apply.py 生成，勿手改）
import SwiftUI

struct SettingsBadge: View {
    let icon: String
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Palette.secondary)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }
}

/// 设置里一行：徽标 + 标题。
struct IconLabel: View {
    let title: LocalizedStringKey
    let icon: String

    init(_ title: LocalizedStringKey, _ icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsBadge(icon: icon)
            Text(title)
        }
    }
}

struct AppBackground: View {
    var body: some View { Palette.background }
}

extension View {
    /// 让系统 grouped 列表的自家底色透出 AppBackground。
    func skinListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(AppBackground().ignoresSafeArea())
    }
}
"""

SETTINGS_LABELS = [
    ('Label("静音音频", systemImage: "speaker.slash")', 'IconLabel("静音音频", "speaker.slash")'),
    ('Label("任务续跑", systemImage: "hourglass")', 'IconLabel("任务续跑", "hourglass")'),
    ('Label("显示会话标题", systemImage: "eye")', 'IconLabel("显示会话标题", "eye")'),
    ('Label("外观", systemImage: "circle.lefthalf.filled")', 'IconLabel("外观", "circle.lefthalf.filled")'),
    ('Label("语言", systemImage: "globe")', 'IconLabel("语言", "globe")'),
    ('Label(title, systemImage: icon)', 'IconLabel(title, icon)'),
    ('Label("默认访问模式", systemImage: "lock.shield")', 'IconLabel("默认访问模式", "lock.shield")'),
]

THEME_PATCHES = [
    (
        "page background",
        '        content.background(system ? Color(.systemGroupedBackground) : Palette.background)',
        '        content.background(AppBackground())',
    ),
    (
        "grouped list",
        "        if system {\n"
        "            content.listStyle(.insetGrouped)\n"
        "        } else {\n"
        "            content\n"
        "                .listStyle(.insetGrouped)\n"
        "                .scrollContentBackground(.hidden)\n"
        "                .background(Palette.background)\n"
        "        }",
        "        if system {\n"
        "            content\n"
        "                .listStyle(.insetGrouped)\n"
        "                .scrollContentBackground(.hidden)\n"
        "                .background(AppBackground())\n"
        "        } else {\n"
        "            content\n"
        "                .listStyle(.insetGrouped)\n"
        "                .scrollContentBackground(.hidden)\n"
        "                .background(AppBackground())\n"
        "        }",
    ),
    (
        "grouped row",
        "        if system {\n"
        "            content\n"
        "        } else {\n"
        "            content.listRowBackground(Palette.grouped).listRowSeparator(.hidden)\n"
        "        }",
        "        if system {\n"
        "            content.listRowBackground(Palette.grouped)\n"
        "        } else {\n"
        "            content.listRowBackground(Palette.grouped).listRowSeparator(.hidden)\n"
        "        }",
    ),
]

OTHER_PATCHES = [
    (APP, "app root",
     "            .background(Palette.background)\n            .ignoresSafeArea()",
     "            .background(AppBackground())\n            .ignoresSafeArea()"),
    (CONV, "conversation page",
     "        .background(Palette.background)\n        .overlay { if blank { hero(model) } }",
     "        .background(AppBackground())\n        .overlay { if blank { hero(model) } }"),
    (CONV, "reasoning page",
     '            .background(Palette.background)\n            .navigationTitle("思考")',
     '            .background(AppBackground())\n            .navigationTitle("思考")'),
    (RECORDS, "records page",
     "        .background(systemLists ? Color(.systemGroupedBackground) : Palette.grouped)",
     "        .background(Palette.grouped)"),
    (POCKET, "pocket page",
     "        .background(systemLists ? Color(.systemGroupedBackground) : Palette.grouped)",
     "        .background(Palette.grouped)"),
    (PANELS, "remote panel",
     "        .background(Color(.systemBackground))\n        .navigationTitle(entry.name)",
     "        .background(Palette.background)\n        .navigationTitle(entry.name)"),
]


def patch(path: pathlib.Path, label: str, old: str, new: str) -> None:
    if not path.exists():
        raise SystemExit(f"skin: missing {path.relative_to(ROOT)} ({label})")
    text = path.read_text(encoding="utf-8")
    if new in text:
        print(f"skin: {path.name}: {label} already applied")
        return
    if old not in text:
        raise SystemExit(f"skin: anchor not found in {path.name}: {label}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"skin: {path.name}: {label} patched")


COLORS = {'Background': 'F4F5F5', 'Grouped': 'FFFFFF', 'Field': 'FFFFFF', 'Bubble': 'E9EFF3', 'TextSecondary': '5C6872', 'Control': 'E6EBEF', 'Stroke': 'D8DEE2', 'Spot': '426784'}

def apply_palette():
    import json
    for name, hexcolor in COLORS.items():
        path = V / 'Assets.xcassets' / (name + '.colorset') / 'Contents.json'
        data = json.loads(path.read_bytes())
        light = next(c for c in data['colors'] if not c.get('appearances'))
        for offset, key in enumerate(('red', 'green', 'blue')):
            light['color']['components'][key] = '0x' + hexcolor[offset*2:offset*2+2]
        path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf8')


def main() -> int:
    apply_palette()
    SKIN.write_text(SKIN_SWIFT, encoding="utf-8")
    print(f"skin: {SKIN.name} written")

    for label, old, new in THEME_PATCHES:
        patch(THEME, label, old, new)

    for path, label, old, new in OTHER_PATCHES:
        patch(path, label, old, new)

    source = SETTINGS.read_text(encoding="utf-8")
    applied = 0
    for old, new in SETTINGS_LABELS:
        if old in source:
            source = source.replace(old, new)
            applied += 1
        elif new not in source:
            raise SystemExit(f"skin: settings label not found: {old}")
    anchor = '        .navigationTitle("设置")'
    anchor_new = '        .skinListBackground()\n        .navigationTitle("设置")'
    if anchor_new not in source:
        if anchor not in source:
            raise SystemExit("skin: settings list anchor not found")
        source = source.replace(anchor, anchor_new, 1)
    SETTINGS.write_text(source, encoding="utf-8")
    print(f"skin: {SETTINGS.name}: {applied} iclabel(s) patched, list background ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
