import SwiftUI

struct ShortcutKeyEditor: View {
    let shortcut: KeyShortcut
    let action: HotKeyAction

    @Environment(HotKeyManager.self) private var hotKeys
    private var capture: ShortcutCaptureSession { hotKeys.capture }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                if shortcut.modifierFlags.contains(.function) {
                    KeyCapChip(text: "🌐︎", scale: .hero)
                }
                ForEach(shortcut.modifiers, id: \.self) { modifier in
                    cap(
                        text: modifierCap(modifier), detail: .modifier(modifier),
                        label: "Edit \(modifier.rawValue.capitalized) key side")
                }
                if shortcut.supportsKeyEquivalent {
                    cap(text: shortcut.keyGlyph, detail: .character, label: "Edit character key mode")
                } else {
                    KeyCapChip(text: shortcut.keyGlyph, scale: .hero)
                }
            }
            .frame(height: Theme.Size.heroKeyCap)

            HStack(spacing: Theme.Spacing.xs) {
                Text(capture.conflict?.owner ?? "Click keys to edit further")
                    .font(Theme.Typography.compactKeyCap)
                    .foregroundStyle(
                        capture.conflict == nil ? Theme.Colors.textSecondary : .orange
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button {
                    capture.detail = capture.detail == .information ? nil : .information
                } label: {
                    SymbolImage(name: "info.circle", size: Theme.Size.compactKeyCap, monochrome: true)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("Explain shortcut key options")
            }
            .frame(height: Theme.Size.shortcutPopoverLine)

            if let detail = capture.detail {
                Divider()
                details(detail)
            }
        }
    }

    private func cap(text: String, detail: ShortcutCaptureSession.Detail, label: String) -> some View {
        Button {
            capture.detail = capture.detail == detail ? nil : detail
        } label: {
            KeyCapChip(text: text, scale: .hero)
                .overlay {
                    if capture.detail == detail {
                        RoundedRectangle(cornerRadius: Theme.Radius.keyCap, style: .continuous)
                            .strokeBorder(Theme.Colors.border, lineWidth: Theme.Size.hairline)
                    }
                }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(label)
    }

    private func modifierCap(_ modifier: KeyShortcut.Modifier) -> String {
        switch shortcut.modifierSide(for: modifier) {
        case .any: modifier.glyph
        case .left: "L" + modifier.glyph
        case .right: "R" + modifier.glyph
        }
    }

    @ViewBuilder
    private func details(_ detail: ShortcutCaptureSession.Detail) -> some View {
        switch detail {
        case .modifier(let modifier):
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("\(modifier.rawValue.capitalized) key")
                    .font(Theme.Typography.compactKeyCap)
                    .foregroundStyle(Theme.Colors.textSecondary)
                ForEach(KeyShortcut.ModifierSide.allCases, id: \.self) { side in
                    option(
                        sideTitle(side), selected: shortcut.modifierSide(for: modifier) == side
                    ) {
                        update(shortcut.settingSide(side, for: modifier))
                    }
                }
            }
        case .character:
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Character key")
                    .font(Theme.Typography.compactKeyCap)
                    .foregroundStyle(Theme.Colors.textSecondary)
                option("Physical Key (Default)", selected: shortcut.keyEquivalent == nil) {
                    update(shortcut.usingPhysicalKey())
                }
                if let character = shortcut.keyEquivalent ?? shortcut.equivalentCharacter {
                    option(
                        "Key Equivalent: \(character.uppercased())",
                        selected: shortcut.keyEquivalent != nil
                    ) {
                        update(shortcut.usingKeyEquivalent(character))
                    }
                }
                Text(
                    shortcut.keyEquivalent == nil
                        ? "Uses the same key position on every keyboard layout."
                        : "Follows this character across keyboard layouts."
                )
                .font(Theme.Typography.compactKeyCap)
                .foregroundStyle(Theme.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        case .information:
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Modifier keys: Any Side, Left or Right.")
                Text(
                    "Character keys: Physical Key uses key position; Key Equivalent follows the character across layouts."
                )
            }
            .font(Theme.Typography.compactKeyCap)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func option(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(title)
                    .font(Theme.Typography.keyCap)
                Spacer()
                if selected {
                    SymbolImage(name: "checkmark", size: Theme.Size.compactKeyCap, monochrome: true)
                }
            }
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Size.shortcutEditorOption)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .fill(selected ? Theme.Colors.selection : Theme.Colors.cardFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityValue(selected ? "Selected" : "")
    }

    private func sideTitle(_ side: KeyShortcut.ModifierSide) -> String {
        switch side {
        case .any: "Any Side"
        case .left: "Left"
        case .right: "Right"
        }
    }

    private func update(_ shortcut: KeyShortcut) {
        capture.updateShortcut(shortcut, action: action, hotKeys: hotKeys)
    }
}
