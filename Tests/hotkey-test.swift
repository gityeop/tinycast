import AppKit
import Carbon.HIToolbox
import Foundation

/// Drives `DoubleTapDetector` on a virtual clock, so every boundary is exact.
@MainActor
private struct Keyboard {
    var detector = DoubleTapDetector()
    private(set) var fired: [DoubleTapModifier] = []

    mutating func press(
        _ modifiers: Set<DoubleTapModifier>, other: Bool = false, at time: TimeInterval
    ) {
        if let modifier = detector.handle(
            .modifiers(modifiers, hasOtherModifiers: other), at: time)
        {
            fired.append(modifier)
        }
    }

    mutating func release(other: Bool = false, at time: TimeInterval) {
        press([], other: other, at: time)
    }

    mutating func otherInput(at time: TimeInterval) {
        if let modifier = detector.handle(.otherInput, at: time) { fired.append(modifier) }
    }

    mutating func tap(
        _ modifier: DoubleTapModifier, at time: TimeInterval, hold: TimeInterval = 0.05
    ) {
        press([modifier], at: time)
        release(at: time + hold)
    }
}

@main
@MainActor
struct DoubleTapDetectorTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expect(_ fired: [DoubleTapModifier], _ expected: [DoubleTapModifier], _ m: String) {
        expect(fired == expected, "\(m) — fired \(fired.map(\.rawValue)), want \(expected.map(\.rawValue))")
    }

    static func main() {
        modifierGlyphs()
        commandActions()
        layoutCharacters()
        hyperChord()
        hyperRetargeting()
        shortcutDetailsPersistence()
        shortcutSides()
        shortcutCharacterMatching()
        shortcutOverlaps()
        shortcutDetailSpelling()
        spelling()
        globeTap()
        globeChord()
        firing()
        timing()
        chords()
        interruptions()
        repeats()
        resetting()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Spelling

    /// Enough of a US layout to spell with; the app reads its own through `ASCIIKeyboardLayout`.
    private static let usKeys = [
        kVK_ANSI_K: "k", kVK_ANSI_1: "1", kVK_ANSI_Keypad1: "1", kVK_ANSI_Slash: "/",
        kVK_ANSI_Equal: "="
    ]
    private static let hyperModifiers = controlKey | optionKey | shiftKey | cmdKey

    static func spelling() {
        let plain = HotKeySpelling(characters: usKeys, hyperModifiers: nil)
        let hyper = HotKeySpelling(characters: usKeys, hyperModifiers: hyperModifiers)
        func combo(_ keyCode: Int, _ modifiers: Int) -> HotKeyBinding {
            .combo(KeyShortcut(carbonKeyCode: keyCode, carbonModifiers: modifiers))
        }
        func roundTrips(_ binding: HotKeyBinding, as text: String, _ spelling: HotKeySpelling) {
            expect(spelling.text(for: binding) == text, "\(text) is how the binding spells")
            expect(spelling.binding(from: text) == binding, "\(text) reads back as the same binding")
        }

        roundTrips(combo(kVK_LeftArrow, controlKey | optionKey), as: "ctrl+option+left", plain)
        roundTrips(combo(kVK_ANSI_K, shiftKey | cmdKey), as: "shift+cmd+k", plain)
        roundTrips(combo(kVK_Space, optionKey), as: "option+space", plain)
        roundTrips(combo(kVK_F5, 0), as: "f5", plain)
        roundTrips(combo(kVK_ANSI_Slash, cmdKey), as: "cmd+/", plain)
        roundTrips(combo(kVK_UpArrow, kEventKeyModifierFnMask | controlKey), as: "fn+ctrl+up", plain)
        roundTrips(combo(kVK_ANSI_Keypad1, cmdKey), as: "cmd+keypad-1", plain)
        roundTrips(combo(kVK_ANSI_1, cmdKey), as: "cmd+1", plain)
        roundTrips(combo(110, controlKey), as: "ctrl+key-110", plain)
        roundTrips(.doubleTap(.command), as: "double-tap cmd", plain)
        roundTrips(.doubleTap(.control), as: "double-tap ctrl", plain)
        roundTrips(.globe, as: "globe", plain)
        roundTrips(.doubleGlobe, as: "double-tap globe", plain)
        roundTrips(combo(kVK_ANSI_K, hyperModifiers), as: "hyper+k", hyper)
        roundTrips(combo(kVK_ANSI_K, controlKey | optionKey | cmdKey), as: "ctrl+option+cmd+k", hyper)

        expect(
            plain.binding(from: " Command+Shift+K ") == combo(kVK_ANSI_K, shiftKey | cmdKey),
            "modifiers read in any order, case and alias")
        expect(
            plain.binding(from: "alt+space") == combo(kVK_Space, optionKey), "alt reads as option")
        expect(
            plain.binding(from: "double-tap command") == .doubleTap(.command),
            "a double-tap reads its modifier's alias")
        expect(
            plain.text(for: combo(kVK_ANSI_K, hyperModifiers)) == "ctrl+option+shift+cmd+k",
            "without a Hyper key the chord is spelled out")
        expect(plain.binding(from: "hyper+k") == nil, "without a Hyper key, hyper means nothing")

        let plusKey = HotKeySpelling(characters: [kVK_ANSI_Equal: "+"], hyperModifiers: nil)
        expect(
            plusKey.binding(from: "cmd++") == combo(kVK_ANSI_Equal, cmdKey),
            "a layout's plus key is spelled after the separator")

        expect(plain.binding(from: "k") == nil, "a bare key is refused, as the recorder refuses it")
        expect(plain.binding(from: "shift+k") == nil, "Shift alone does not command")
        expect(plain.binding(from: "cmd+") == nil, "a chord needs a key")
        expect(plain.binding(from: "cmd+nope") == nil, "an unknown key is refused")
        expect(plain.binding(from: "cmd+key-999") == nil, "a raw key code must be a real one")
        expect(plain.binding(from: "double-tap fn") == nil, "fn has no double-tap")
    }

    // MARK: - Model

    static func shortcutDetailsPersistence() {
        let legacy = Data(
            #"{"combo":{"_0":{"carbonKeyCode":40,"carbonModifiers":256}}}"#.utf8)
        let decoded = try? JSONDecoder().decode(HotKeyBinding.self, from: legacy)
        expect(
            decoded?.shortcut == KeyShortcut(carbonKeyCode: kVK_ANSI_K, carbonModifiers: cmdKey),
            "an existing saved combo remains the same physical shortcut")
        expect(decoded?.shortcut?.modifierSide(for: .command) == .any, "old combos use either side")
        expect(decoded?.shortcut?.keyEquivalent == nil, "old combos keep physical key matching")
        expect(decoded?.shortcut?.requiresEventTap == false, "old combos retain Carbon registration")

        let detailed = KeyShortcut(
            carbonKeyCode: kVK_ANSI_K, carbonModifiers: shiftKey | cmdKey,
            modifierSides: [.shift: .left, .command: .right], keyEquivalent: "k")
        let encoded = try? JSONEncoder().encode(HotKeyBinding.combo(detailed))
        expect(
            encoded.flatMap { try? JSONDecoder().decode(HotKeyBinding.self, from: $0) }
                == .combo(detailed),
            "the binding payload used by preferences and backups preserves all key details")
        expect(
            detailed.usingPhysicalKey().modifierSides == detailed.modifierSides,
            "switching character mode keeps modifier sides")
        expect(
            detailed.usingPhysicalKey().keyEquivalent == nil,
            "physical mode clears the saved character")
        expect(
            detailed.settingSide(.any, for: .command).modifierSide(for: .command) == .any,
            "a modifier can be restored to either side")

        let hyper = combo([.control, .option, .command])
            .settingSide(.right, for: .command).usingKeyEquivalent("g")
        let retargeted = hyper.retargetingHyper(includesShift: true)
        expect(
            retargeted.modifierSide(for: .command) == .right && retargeted.keyEquivalent == "g",
            "changing the Hyper chord keeps modifier and character details")
    }

    static func shortcutSides() {
        let deviceBits: [(KeyShortcut.Modifier, UInt, UInt)] = [
            (.control, 0x0000_0001, 0x0000_2000),
            (.option, 0x0000_0020, 0x0000_0040),
            (.shift, 0x0000_0002, 0x0000_0004),
            (.command, 0x0000_0008, 0x0000_0010)
        ]
        for (modifier, leftBit, rightBit) in deviceBits {
            let flags = modifier.flag.union(.command)
            let shortcut = KeyShortcut(
                carbonKeyCode: kVK_ANSI_K,
                carbonModifiers: KeyShortcut.carbonModifiers(from: flags))
            let leftFlags = NSEvent.ModifierFlags(rawValue: flags.rawValue | leftBit)
            let rightFlags = NSEvent.ModifierFlags(rawValue: flags.rawValue | rightBit)
            let left = shortcut.settingSide(.left, for: modifier)
            let right = shortcut.settingSide(.right, for: modifier)
            expect(
                shortcut.matches(keyCode: kVK_ANSI_K, modifierFlags: leftFlags, character: "k")
                    && shortcut.matches(
                        keyCode: kVK_ANSI_K, modifierFlags: rightFlags, character: "k"),
                "an any-side \(modifier) shortcut accepts both physical modifiers")
            expect(
                left.matches(keyCode: kVK_ANSI_K, modifierFlags: leftFlags, character: "k")
                    && !left.matches(
                        keyCode: kVK_ANSI_K, modifierFlags: rightFlags, character: "k"),
                "a left \(modifier) shortcut rejects the right modifier")
            expect(
                right.matches(keyCode: kVK_ANSI_K, modifierFlags: rightFlags, character: "k")
                    && !right.matches(
                        keyCode: kVK_ANSI_K, modifierFlags: leftFlags, character: "k"),
                "a right \(modifier) shortcut rejects the left modifier")
            expect(
                left.matches(
                    keyCode: kVK_ANSI_K, modifierFlags: leftFlags.union(.capsLock), character: "k"),
                "Caps Lock does not change a side-specific \(modifier) shortcut")
            expect(left.requiresEventTap && right.requiresEventTap, "side matching uses the event tap")
            expect(!shortcut.requiresEventTap, "an ordinary physical chord keeps the Carbon engine")
        }
        let command = KeyShortcut(carbonKeyCode: kVK_ANSI_K, carbonModifiers: cmdKey)
            .settingSide(.left, for: .command)
        let leftCommand = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 8)
        expect(
            !command.matches(
                keyCode: kVK_ANSI_K, modifierFlags: leftCommand.union(.shift), character: "k"),
            "an extra generic modifier does not trigger a side-specific shortcut")
    }

    static func shortcutCharacterMatching() {
        let physical = KeyShortcut(carbonKeyCode: kVK_ANSI_K, carbonModifiers: cmdKey)
        let character = physical.usingKeyEquivalent("k")
        expect(
            physical.matches(keyCode: kVK_ANSI_K, modifierFlags: [.command], character: "s"),
            "physical mode retains its position when another layout types a different letter")
        expect(
            !physical.matches(keyCode: kVK_ANSI_S, modifierFlags: [.command], character: "k"),
            "physical mode does not follow its old letter to a new position")
        expect(
            character.matches(keyCode: kVK_ANSI_S, modifierFlags: [.command], character: "k"),
            "character mode follows the saved letter to a different key position")
        expect(
            !character.matches(keyCode: kVK_ANSI_K, modifierFlags: [.command], character: "s"),
            "character mode rejects its old position after its letter changes")
        expect(character.requiresEventTap, "character matching uses the event tap")
        expect(
            !character.matches(keyCode: kVK_ANSI_S, modifierFlags: [.option], character: "k"),
            "the right character alone cannot bypass the required modifiers")
        let sided = character.settingSide(.right, for: .command)
        let rightCommand = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 16)
        let leftCommand = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.command.rawValue | 8)
        expect(
            sided.matches(keyCode: kVK_ANSI_S, modifierFlags: rightCommand, character: "k")
                && !sided.matches(
                    keyCode: kVK_ANSI_S, modifierFlags: leftCommand, character: "k"),
            "character matching also enforces the selected modifier side")
    }

    static func shortcutOverlaps() {
        let physical = KeyShortcut(carbonKeyCode: kVK_ANSI_K, carbonModifiers: cmdKey)
        let left = physical.settingSide(.left, for: .command)
        let right = physical.settingSide(.right, for: .command)
        let usLayout: (Int, Int) -> String? = { code, _ in
            code == kVK_ANSI_K ? "k" : code == kVK_ANSI_S ? "s" : nil
        }
        expect(
            physical.overlaps(with: left, characterForKeyCode: usLayout)
                && left.overlaps(with: physical, characterForKeyCode: usLayout),
            "any-side and left-side registrations conflict in both directions")
        expect(
            !left.overlaps(with: right, characterForKeyCode: usLayout),
            "left and right versions can be assigned to separate actions")
        expect(
            physical.overlaps(
                with: physical.usingKeyEquivalent("k"), characterForKeyCode: usLayout),
            "physical and character shortcuts conflict when this layout maps them to the same key")
        let movedLayout: (Int, Int) -> String? = { code, _ in
            code == kVK_ANSI_K ? "s" : code == kVK_ANSI_S ? "k" : nil
        }
        let equivalent = physical.usingKeyEquivalent("k")
        expect(
            !physical.overlaps(with: equivalent, characterForKeyCode: movedLayout),
            "a character shortcut stops conflicting with its old physical position")
        expect(
            KeyShortcut(carbonKeyCode: kVK_ANSI_S, carbonModifiers: cmdKey)
                .overlaps(with: equivalent, characterForKeyCode: movedLayout),
            "a character shortcut conflicts with its new physical position")
        let commandLayout: (Int, Int) -> String? = { code, modifiers in
            guard code == kVK_ANSI_K else { return nil }
            return modifiers & cmdKey != 0 ? "k" : "s"
        }
        expect(
            physical.overlaps(with: equivalent, characterForKeyCode: commandLayout),
            "overlap lookup uses the layout's Command table for Command shortcuts")
    }

    static func shortcutDetailSpelling() {
        let spelling = HotKeySpelling(characters: usKeys, hyperModifiers: hyperModifiers)
        let detailed = KeyShortcut(
            carbonKeyCode: kVK_ANSI_K, carbonModifiers: shiftKey | cmdKey,
            modifierSides: [.shift: .left, .command: .right], keyEquivalent: "k")
        expect(
            spelling.text(for: .combo(detailed)) == "left-shift+right-cmd+character:k",
            "the settings file spells modifier sides and character mode explicitly")
        expect(
            spelling.binding(from: "left-shift+right-cmd+character:k") == .combo(detailed),
            "the settings file restores modifier sides and character mode")
        let hyper = combo([.control, .option, .shift, .command])
            .settingSide(.right, for: .command)
        let text = spelling.text(for: .combo(hyper))
        expect(!text.contains("hyper"), "Hyper spelling cannot hide a modifier side restriction")
        expect(spelling.binding(from: text) == .combo(hyper), "a detailed Hyper chord round-trips")
    }

    static func globeTap() {
        var detector = GlobeTapDetector()
        func globe(
            _ down: Bool, at time: TimeInterval, physical: Bool = true, other: Bool = false
        ) -> GlobeTapDetector.Gesture? {
            detector.handle(
                isGlobeKey: physical, functionDown: down, hasOtherModifiers: other, at: time)
        }

        expect(globe(true, at: 0) == nil, "Globe press waits for release")
        expect(globe(false, at: 0.05) == .single, "lone Globe fires on release")
        expect(globe(false, at: 0.10) == nil, "a second release without a press does nothing")
        expect(globe(true, at: 0.25) == nil, "a second Globe press waits for release")
        expect(globe(false, at: 0.30) == .double, "two quick Globe presses form a double tap")

        _ = globe(true, at: 1)
        _ = globe(true, at: 1.02, physical: false, other: true)
        expect(globe(false, at: 1.05) == nil, "another modifier cancels Globe")

        _ = globe(true, at: 2)
        detector.cancel()
        expect(globe(false, at: 2.05) == nil, "a key press or click cancels Globe")
        expect(globe(true, at: 3, physical: false) == nil, "an F-key cannot start Globe")
        expect(globe(false, at: 3.05, physical: false) == nil, "an F-key cannot finish Globe")

        _ = globe(true, at: 4)
        expect(globe(false, at: 4.05) == .single, "first release remains a single candidate")
        _ = globe(true, at: 4.40)
        expect(globe(false, at: 4.45) == .single, "a late second press starts a new tap")
        _ = globe(true, at: 5)
        expect(globe(false, at: 5.30) == nil, "holding Globe is not a tap")

        for binding in [HotKeyBinding.globe, .doubleGlobe] {
            let encoded = try? JSONEncoder().encode(binding)
            expect(
                encoded.flatMap { try? JSONDecoder().decode(HotKeyBinding.self, from: $0) }
                    == binding,
                "\(binding) round-trips through the existing persistence format")
        }
        expect(HotKeyBinding.globe.keycaps == ["🌐︎"], "Globe uses one monochrome keycap")
        expect(
            HotKeyBinding.doubleGlobe.keycaps == ["🌐︎", "🌐︎"],
            "double Globe renders as two monochrome keycaps")
    }

    static func globeChord() {
        let shortcut = KeyShortcut(keyCode: kVK_ANSI_J, modifierFlags: [.function])
        expect(shortcut != nil, "Globe alone can modify a letter")
        expect(
            shortcut?.carbonModifiers == kEventKeyModifierFnMask,
            "Globe uses Carbon's fn modifier bit")
        expect(shortcut?.keycaps == ["🌐︎", "J"], "Globe and the key have separate caps")
        expect(
            KeyShortcut(keyCode: kVK_ANSI_J, modifierFlags: [.function, .command])?.modifierFlags
                == [.function, .command],
            "Globe combines with ordinary modifiers")
        expect(
            KeyShortcut(carbonKeyCode: kVK_ANSI_J, carbonModifiers: Int.max).carbonModifiers
                == KeyShortcut.carbonModifiers(from: [.function, .control, .option, .shift, .command]),
            "decoding keeps fn but still discards unrelated modifier bits")
    }

    static func modifierGlyphs() {
        expect(DoubleTapModifier.allCases.count == 4, "exactly four modifiers are eligible")
        expect(
            Set(DoubleTapModifier.allCases.map(\.glyph)) == ["⌃", "⌥", "⇧", "⌘"],
            "the glyphs are the four macOS modifier symbols")
        expect(
            DoubleTapModifier.allCases.allSatisfy { $0.keycaps == [$0.glyph, $0.glyph] },
            "a double-tap renders as its glyph twice")
        expect(
            DoubleTapModifier.allCases.map(\.rawValue)
                == ["control", "option", "shift", "command"],
            "raw values are the persisted spelling and stay in canonical ⌃⌥⇧⌘ order")
    }

    static func layoutCharacters() {
        let keyCodes = [kVK_ANSI_K, kVK_ANSI_X, kVK_ANSI_Q, kVK_ANSI_Comma, kVK_ANSI_Period]
        let characters = keyCodes.compactMap { ASCIIKeyboardLayout.character(for: $0) }
        expect(
            characters.count == keyCodes.count,
            "the ASCII-capable layout translates every ANSI key a palette chord uses")
        expect(
            characters.allSatisfy { $0.unicodeScalars.allSatisfy(\.isASCII) },
            "the shortcut character stays ASCII while a non-ASCII input source is active")
        expect(
            keyCodes.allSatisfy {
                ASCIIKeyboardLayout.character(for: $0, modifiers: UInt32(cmdKey >> 8)) != nil
            },
            "a layout's Command table resolves the same keys, so ⌘ chords never lose their letter")
    }

    // MARK: - Built-in command mappings

    static func commandActions() {
        expect(
            HotKeyAction.systemAction(id: .toggleMicrophoneMute).defaultsKey
                == "hotkey.systemAction.toggle-microphone-mute",
            "microphone mute persists under its own global hotkey key")
        expect(
            HotKeyAction.systemAction(id: .toggleMicrophoneMute).defaultsKey
                != HotKeyAction.systemAction(id: .toggleMute).defaultsKey,
            "microphone and output mute can have independent hotkeys")
        let unbindable = Set(CommandID.allCases.filter { $0.hotKeyAction == nil })
        expect(
            unbindable == [.openInBrowser, .runShellCommand, .quit],
            "only the query-driven pair and Quit are unbindable — got \(unbindable.map(\.name))")
        expect(
            CommandID.allCases.allSatisfy {
                unbindable.contains($0) || $0.hotKeyAction == .command($0)
            },
            "every other command binds to its own action, so every row gets a recorder")

        // Keyed on the raw value, not the position, so reordering the enum cannot move a binding.
        for id in CommandID.allCases where !unbindable.contains(id) {
            expect(
                id.hotKeyAction?.defaultsKey == "hotkey.\(id.rawValue)",
                "\(id.name) persists under hotkey.\(id.rawValue)")
            expect(
                HotKeyAction.builtInActions.contains(.command(id)),
                "\(id.name) is registered at launch like every other fixed action")
        }
        expect(
            HotKeyAction.builtInActions.contains(.togglePalette),
            "the launcher toggle is bindable without a command row of its own")

        // Every action reaches the launcher as well as a shortcut; `CommandID.init` is exhaustive.
        expect(
            BuiltInQuickAction.allCases.allSatisfy { CommandID($0).name == $0.title },
            "each Quick Action's command carries the action's own title")
        expect(
            Set(BuiltInQuickAction.allCases.map(CommandID.init)).count == BuiltInQuickAction.allCases.count,
            "no two Quick Actions share a launcher command")
        expect(
            Set(HotKeyAction.builtInActions.map(\.defaultsKey)).count
                == HotKeyAction.builtInActions.count,
            "no two built-in actions share a defaults key, which would bind them together")
    }

    // MARK: - The Hyper chord

    /// A combo on the G key, spelled in Carbon like the on-disk shape.
    private static func combo(_ flags: NSEvent.ModifierFlags) -> KeyShortcut {
        KeyShortcut(
            carbonKeyCode: kVK_ANSI_G, carbonModifiers: KeyShortcut.carbonModifiers(from: flags))
    }

    private static func caps(_ flags: NSEvent.ModifierFlags, includesShift: Bool?) -> [String] {
        KeyShortcut.collapsedModifierSymbols(
            from: flags,
            hyperChord: includesShift.map { KeyShortcut.hyperChord(includesShift: $0) })
    }

    static func hyperChord() {
        expect(
            KeyShortcut.hyperChord(includesShift: false) == [.control, .option, .command],
            "Hyper without Include Shift is exactly ⌃⌥⌘")
        expect(
            KeyShortcut.hyperChord(includesShift: true) == [.control, .option, .shift, .command],
            "Include Shift adds ⇧ and nothing else")

        for includesShift in [false, true] {
            let chord = KeyShortcut.hyperChord(includesShift: includesShift)
            expect(
                caps(chord, includesShift: includesShift) == ["✦"],
                "the chord itself collapses to a lone ✦ (shift \(includesShift))")
            expect(
                caps(chord.union(.capsLock), includesShift: includesShift) == ["✦"],
                "a stray non-shortcut flag doesn't defeat the collapse (shift \(includesShift))")
            expect(
                caps(chord, includesShift: nil) == KeyShortcut.modifierSymbols(from: chord),
                "with no Hyper key configured the chord renders literally (shift \(includesShift))")
        }

        // ⌃⌥⌘ is a subset of ⌃⌥⇧⌘, so only the shift-off chord can collapse under the wider set.
        expect(
            caps([.control, .option, .command], includesShift: true) == ["⌃", "⌥", "⌘"],
            "the narrower chord doesn't collapse while Include Shift is on")
        expect(
            caps([.control, .option, .shift, .command], includesShift: false) == ["✦", "⇧"],
            "an extra modifier trails ✦ in canonical order")
        expect(
            caps([.command, .shift], includesShift: false) == ["⇧", "⌘"],
            "an ordinary combo is untouched, and stays in ⌃⌥⇧⌘ order rather than press order")

        expect(
            KeyShortcut(
                keyCode: kVK_ANSI_G,
                modifierFlags: KeyShortcut.hyperChord(
                    includesShift: true))?.carbonModifiers
                == combo([.control, .option, .shift, .command]).carbonModifiers,
            "recording while Hyper is held captures exactly the chord")
    }

    static func hyperRetargeting() {
        let narrow = combo([.control, .option, .command])
        let wide = combo([.control, .option, .shift, .command])

        expect(narrow.retargetingHyper(includesShift: true) == wide, "⌃⌥⌘G follows ⇧ going on")
        expect(wide.retargetingHyper(includesShift: false) == narrow, "⌃⌥⇧⌘G follows ⇧ going off")
        expect(
            narrow.retargetingHyper(includesShift: true).retargetingHyper(includesShift: false)
                == narrow,
            "the chord round-trips across a flip and back")
        for includesShift in [false, true] {
            let target = includesShift ? wide : narrow
            expect(
                target.retargetingHyper(includesShift: includesShift) == target,
                "retargeting is idempotent, so an import can't corrupt a matching chord")
        }

        expect(
            narrow.retargetingHyper(includesShift: true).carbonKeyCode == kVK_ANSI_G,
            "only the modifiers move; the key is preserved")
        expect(
            combo([.control, .option, .command, .capsLock]).retargetingHyper(includesShift: true)
                == wide,
            "the masking initializer keeps a stray flag out of the retargeted chord")

        // Anything that isn't the other chord is left exactly as recorded.
        for flags in [[.command, .shift], [.option], [.control, .option], []]
            as [NSEvent
            .ModifierFlags]
        {
            let shortcut = combo(flags)
            for includesShift in [false, true] {
                expect(
                    shortcut.retargetingHyper(includesShift: includesShift) == shortcut,
                    "\(KeyShortcut.modifierSymbols(from: flags).joined()) is not a Hyper chord")
            }
        }
    }

    // MARK: - Firing

    static func firing() {
        for modifier in DoubleTapModifier.allCases {
            var keyboard = Keyboard()
            keyboard.tap(modifier, at: 0)
            expect(keyboard.fired, [], "\(modifier.rawValue): one tap alone doesn't fire")
            keyboard.tap(modifier, at: 0.15)
            expect(keyboard.fired, [modifier], "\(modifier.rawValue): a clean double-tap fires")
        }

        // Firing is on the second release, not the second press.
        var keyboard = Keyboard()
        keyboard.tap(.command, at: 0)
        keyboard.press([.command], at: 0.15)
        expect(keyboard.fired, [], "the second press alone doesn't fire")
        keyboard.release(at: 0.20)
        expect(keyboard.fired, [.command], "the second release fires")
    }

    // MARK: - Timing

    static func timing() {
        var slowFirst = Keyboard()
        slowFirst.tap(.command, at: 0, hold: DoubleTapDetector.maxHold + 0.01)
        slowFirst.tap(.command, at: 0.5)
        expect(slowFirst.fired, [], "a held first press isn't a tap")

        var slowSecond = Keyboard()
        slowSecond.tap(.command, at: 0)
        slowSecond.tap(.command, at: 0.10, hold: DoubleTapDetector.maxHold + 0.01)
        expect(slowSecond.fired, [], "a held second press isn't a tap")

        var lateGap = Keyboard()
        lateGap.tap(.command, at: 0, hold: 0.05)
        lateGap.tap(.command, at: 0.05 + DoubleTapDetector.maxGap + 0.01)
        expect(lateGap.fired, [], "a second tap after the gap doesn't fire")

        // Just inside both windows: the slowest double-tap that still counts.
        let epsilon = 0.001
        var atLimit = Keyboard()
        atLimit.tap(.command, at: 0, hold: DoubleTapDetector.maxHold - epsilon)
        atLimit.tap(
            .command, at: DoubleTapDetector.maxHold + DoubleTapDetector.maxGap - 2 * epsilon,
            hold: DoubleTapDetector.maxHold - epsilon)
        expect(atLimit.fired, [.command], "the slowest qualifying double-tap still fires")

        // A late second tap becomes the new first tap rather than being discarded.
        var rolling = Keyboard()
        rolling.tap(.command, at: 0)
        rolling.tap(.command, at: 1.0)
        expect(rolling.fired, [], "the late tap doesn't fire")
        rolling.tap(.command, at: 1.15)
        expect(rolling.fired, [.command], "but it seeds the next pair")
    }

    // MARK: - Chords

    static func chords() {
        var joined = Keyboard()
        joined.tap(.command, at: 0)
        joined.press([.command], at: 0.15)
        joined.press([.command, .shift], at: 0.17)
        joined.press([.command], at: 0.19)
        joined.release(at: 0.21)
        expect(joined.fired, [], "a chord unwinding back to one modifier isn't a tap")

        var chorded = Keyboard()
        chorded.press([.command, .shift], at: 0)
        chorded.release(at: 0.05)
        chorded.press([.command, .shift], at: 0.10)
        chorded.release(at: 0.15)
        expect(chorded.fired, [], "double-tapping a two-modifier chord doesn't fire")

        var mixed = Keyboard()
        mixed.tap(.command, at: 0)
        mixed.tap(.shift, at: 0.15)
        expect(mixed.fired, [], "two different modifiers aren't a double-tap")
        mixed.tap(.shift, at: 0.30)
        expect(mixed.fired, [.shift], "but the second one starts its own pair")

        var withFn = Keyboard()
        withFn.press([.command], other: true, at: 0)
        withFn.release(other: true, at: 0.05)
        withFn.press([.command], other: true, at: 0.10)
        withFn.release(other: true, at: 0.15)
        // A latched bit like Caps Lock would disqualify every press while it stays set.
        expect(withFn.fired, [], "fn held alongside disqualifies the press")

        // The poison clears once the extra modifier is gone.
        var recovered = Keyboard()
        recovered.press([.command], other: true, at: 0)
        recovered.release(at: 0.05)
        recovered.tap(.command, at: 0.10)
        recovered.tap(.command, at: 0.25)
        expect(recovered.fired, [.command], "a clean pair after the poisoned one still fires")
    }

    // MARK: - Interruptions

    static func interruptions() {
        var typed = Keyboard()
        typed.tap(.command, at: 0)
        typed.otherInput(at: 0.08)
        typed.tap(.command, at: 0.15)
        expect(typed.fired, [], "a key press between taps cancels the pair")

        var shortcut = Keyboard()
        shortcut.press([.command], at: 0)
        shortcut.otherInput(at: 0.02)
        shortcut.release(at: 0.05)
        shortcut.tap(.command, at: 0.10)
        expect(shortcut.fired, [], "⌘K then ⌘ isn't a double-tap")

        var clicked = Keyboard()
        clicked.tap(.option, at: 0)
        clicked.otherInput(at: 0.10)
        clicked.tap(.option, at: 0.14)
        expect(clicked.fired, [], "a click between taps cancels the pair")
    }

    // MARK: - Repeats

    static func repeats() {
        var keyboard = Keyboard()
        keyboard.tap(.command, at: 0)
        keyboard.tap(.command, at: 0.15)
        expect(keyboard.fired, [.command], "the pair fires")
        keyboard.tap(.command, at: 0.30)
        expect(keyboard.fired, [.command], "a triple-tap doesn't fire twice")
        keyboard.tap(.command, at: 0.45)
        expect(keyboard.fired, [.command, .command], "the next full pair fires again")
    }

    // MARK: - Reset

    static func resetting() {
        var keyboard = Keyboard()
        keyboard.tap(.command, at: 0)
        keyboard.detector.reset()
        keyboard.tap(.command, at: 0.15)
        expect(keyboard.fired, [], "reset drops the pending tap")

        // Reset also forgets held modifiers, so the next press still reads as a clean start.
        var stuck = Keyboard()
        stuck.press([.command], at: 0)
        stuck.detector.reset()
        stuck.tap(.command, at: 0.10)
        stuck.tap(.command, at: 0.25)
        expect(stuck.fired, [.command], "reset clears a half-held press")
    }
}
