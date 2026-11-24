#!/usr/bin/env python3
"""Apply the dsh-go style skin layer to the iOS app before building.

Run by CI from scripts/build-engine.sh. Idempotent; fails loudly if the
upstream source no longer matches, so a silent no-op build is impossible.

What it changes:
  * writes app/DshIOS/Views/SkinStyle.swift (badge + gradient + modifier)
  * app/DshIOS/Views/SettingsView.swift: row labels become IconLabel,
    and the settings list gets .skinListBackground().
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SETTINGS = ROOT / "app" / "DshIOS" / "Views" / "SettingsView.swift"
SKIN = ROOT / "app" / "DshIOS" / "Views" / "SkinStyle.swift"

SKIN_SWIFT = r"""// dsh-go 风格皮肤层（由 tooling/skin/apply.py 生成，勿手改）
import SwiftUI

/// 图标底色：按 SF Symbol 名归类，未命中的用强调蓝。
enum BadgeTint {
    static func color(for icon: String) -> Color {
        let n = icon.lowercased()
        if n.contains("key") { return rgb(240, 176, 64) }
        if n.contains("mic") || n.contains("wave") { return rgb(150, 110, 235) }
        if n.contains("speaker") || n.contains("phone") { return rgb(240, 140, 80) }
        if n.contains("image") || n.contains("photo") || n.contains("sparkles") { return rgb(235, 120, 160) }
        if n.contains("lock") || n.contains("shield") { return rgb(60, 175, 120) }
        if n.contains("puzzle") { return rgb(120, 130, 235) }
        if n.contains("clock") || n.contains("hourglass") { return rgb(110, 120, 210) }
        if n.contains("eye") { return rgb(80, 170, 200) }
        if n.contains("circle.lefthalf") { return rgb(120, 130, 150) }
        if n.contains("globe") { return rgb(90, 160, 220) }
        if n.contains("wrench") { return rgb(130, 140, 160) }
        if n.contains("info") { return rgb(140, 150, 170) }
        if n.contains("archive") { return rgb(170, 140, 110) }
        return rgb(60, 109, 240)
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255.0, green: g / 255.0, blue: b / 255.0)
    }
}

/// 彩色圆角方块 + 白色符号。
struct SettingsBadge: View {
    let icon: String
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                BadgeTint.color(for: icon),
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            )
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

/// 页面底色：浅蓝紫渐变；深色模式交回系统。
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if scheme == .dark {
            Color(.systemGroupedBackground)
        } else {
            LinearGradient(
                colors: [
                    Color(red: 218.0 / 255.0, green: 227.0 / 255.0, blue: 251.0 / 255.0),
                    Color(red: 237.0 / 255.0, green: 235.0 / 255.0, blue: 248.0 / 255.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

extension View {
    /// 让系统 grouped 列表的自家底色透出 AppBackground。
    func skinListBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(AppBackground().ignoresSafeArea())
    }
}
"""

# (原样, 替换) —— 只在旧串存在且新串尚不存在时替换
REPLACEMENTS = [
    ('Label("静音音频", systemImage: "speaker.slash")', 'IconLabel("静音音频", "speaker.slash")'),
    ('Label("任务续跑", systemImage: "hourglass")', 'IconLabel("任务续跑", "hourglass")'),
    ('Label("显示会话标题", systemImage: "eye")', 'IconLabel("显示会话标题", "eye")'),
    ('Label("外观", systemImage: "circle.lefthalf.filled")', 'IconLabel("外观", "circle.lefthalf.filled")'),
    ('Label("语言", systemImage: "globe")', 'IconLabel("语言", "globe")'),
    ('Label(title, systemImage: icon)', 'IconLabel(title, icon)'),
    ('Label("默认访问模式", systemImage: "lock.shield")', 'IconLabel("默认访问模式", "lock.shield")'),
]

ANCHOR = '        .navigationTitle("设置")'
ANCHOR_NEW = '        .skinListBackground()\n        .navigationTitle("设置")'


def main() -> int:
    if not SETTINGS.exists():
        print(f"skin: missing {SETTINGS}", file=sys.stderr)
        return 1

    SKIN.write_text(SKIN_SWIFT, encoding="utf-8")
    source = SETTINGS.read_text(encoding="utf-8")
    applied, skipped = 0, []

    for old, new in REPLACEMENTS:
        if old in source:
            source = source.replace(old, new)
            applied += 1
        elif new in source:
            skipped.append(new)
        else:
            print(f"skin: pattern not found: {old}", file=sys.stderr)
            return 1

    if ANCHOR_NEW in source:
        background = True
    elif ANCHOR in source:
        source = source.replace(ANCHOR, ANCHOR_NEW, 1)
        background = True
    else:
        print("skin: settings list anchor not found", file=sys.stderr)
        return 1

    SETTINGS.write_text(source, encoding="utf-8")
    print(f"skin: {SKIN.name} written; labels {applied} applied, {len(skipped)} already; background {background}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
