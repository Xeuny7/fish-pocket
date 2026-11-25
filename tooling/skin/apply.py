#!/usr/bin/env python3
"""Apply the dark-saas skin to the whole iOS app before building.

Run by CI from scripts/build-engine.sh. Idempotent. Structural anchors abort the
build when missing; cosmetic ones only warn.

Palette: near-black canvas, layered slate panels, electric-blue accent, teal /
amber status, hairline borders, tighter label tracking.
"""
import json
import pathlib

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

SKIN_SWIFT = r"""// dark-saas 皮肤层（由 tooling/skin/apply.py 生成，勿手改）
import SwiftUI

/// 设置行左侧方块徽标：28x28、8pt 圆角、深色底 + 电光蓝字形。
struct SettingsBadge: View {
    let icon: String
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Palette.link)
            .frame(width: 28, height: 28)
            .background(Palette.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

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

/// 全局画布：近黑底 + 顶部一层极淡强调色辉光（不是整页渐变）。
struct AppBackground: View {
    var body: some View {
        Palette.background
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Palette.link.opacity(0.10), Palette.link.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
                .allowsHitTesting(false)
            }
    }
}

/// 分组标题：小号、字距略放、次要色。
struct SaaSGroupCaption: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Palette.faint)
    }
}

extension View {
    func skinListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(AppBackground().ignoresSafeArea())
    }

    func saasGroupCaption() -> some View { modifier(SaaSGroupCaption()) }
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
     "            .preferredColorScheme(.dark)\n            .background(AppBackground())\n            .ignoresSafeArea()"),
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

# 只影响观感、锚点可能随上游漂移：找不到就告警，不阻断构建。
SOFT_PATCHES = [
    (THEME, "switch tint", ".tint(.green)", ".tint(Palette.link)"),
    (THEME, "row hairline", "listRowSeparator(.hidden)",
     "listRowSeparator(.visible).listRowSeparatorTint(Palette.stroke)"),
    (SETTINGS, "grouped bg", "Color(.secondarySystemGroupedBackground)", "Palette.grouped"),
]

COLORS = {
    "Background": "0B0E13",
    "Grouped": "141922",
    "Field": "171D27",
    "Bubble": "1B2431",
    "Control": "1E2733",
    "Stroke": "232B38",
    "Ink": "E6EDF6",
    "OnInk": "0B0E13",
    "TextSecondary": "93A2B8",
    "TextFaint": "5D6B80",
    "Link": "5E9BFF",
    "Spot": "5E9BFF",
    "AccentColor": "5E9BFF",
    "StatusRunning": "2DD4BF",
    "StatusWaiting": "F5B34C",
    "Scrim": "000000",
    "DiffAddBackground": "10291B",
    "DiffAddText": "7DD3A0",
    "DiffDeleteBackground": "2E171C",
    "DiffDeleteText": "F08A8A",
}


def apply_palette() -> None:
    """每个 Color Set 的 light 与 dark 都写成同一套深色，避免亮色模式下漏白。"""
    for name, hexcolor in COLORS.items():
        path = V / "Assets.xcassets" / (name + ".colorset") / "Contents.json"
        if not path.exists():
            print(f"skin: color set missing {name} (skipped)")
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        comps = {
            "red": "0x" + hexcolor[0:2],
            "green": "0x" + hexcolor[2:4],
            "blue": "0x" + hexcolor[4:6],
            "alpha": "1.000",
        }
        for entry in data.get("colors", []):
            entry["color"]["color-space"] = "srgb"
            entry["color"]["components"] = dict(comps)
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        print(f"skin: color {name} -> #{hexcolor}")


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


def soft_patch(path: pathlib.Path, label: str, old: str, new: str) -> None:
    try:
        if not path.exists():
            print(f"skin: warn missing {path.name} ({label})")
            return
        text = path.read_text(encoding="utf-8")
        if old not in text:
            print(f"skin: warn {path.name}: {label} anchor absent (skipped)")
            return
        path.write_text(text.replace(old, new), encoding="utf-8")
        print(f"skin: {path.name}: {label} patched (soft)")
    except Exception as exc:  # noqa: BLE001
        print(f"skin: warn {path.name}: {label} failed: {exc}")


def main() -> int:
    apply_palette()
    SKIN.write_text(SKIN_SWIFT, encoding="utf-8")
    print(f"skin: {SKIN.name} written")

    for label, old, new in THEME_PATCHES:
        patch(THEME, label, old, new)

    for path, label, old, new in OTHER_PATCHES:
        patch(path, label, old, new)

    for path, label, old, new in SOFT_PATCHES:
        soft_patch(path, label, old, new)

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
