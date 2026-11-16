# Fantastical Visual Redesign, Stage 1 (foundation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stark follows the phone's light/dark appearance and looks like Fantastical (grouped light-grey ground, white rounded cards, system font, blue accent, round buttons) without changing any layout or behaviour.

**Architecture:** Keep the `Colors`/`Fonts`/`Spacing` token names so call sites barely change; make the values adaptive (light/dark), swap the mono font for the system font behind `Fonts.mono`, make `SquareButton` round, remove forced dark, then restyle forms and list screens to grouped cards. All in the app target (styling only, no StarkKit logic).

**Tech Stack:** SwiftUI, iOS 17+ (glass on iOS 26 via `#available`), XcodeGen not used (committed pbxproj, synchronized groups).

**Spec:** `docs/superpowers/specs/2026-11-15-fantastical-visual-design.md`

## Global Constraints

- Styling only: no behaviour, data or StarkKit changes. `cd ios && swift test` must stay at 1094 passing.
- Colors only through `Theme.swift` tokens. Allowed exception: `Color(hex:)` of an Apple calendar's own colour (`AgendaRow.swift:300`, `AppleSettingsView.swift:135`).
- Tokens (adaptive, light / dark): `background` (grouped ground) #F2F2F7 / #000000; new `card` #FFFFFF / #1C1C1E; `text` #1C1C1E / #F2F2F7; `textSecondary` #8E8E93 both; `separator` #D1D1D6 / #38383A; `accent` #3B82F6 / #5B9BFF; `checkboxBorder` #C7C7CC / #636366; `eventDot` stays #8E5FD9 (until stages 2-3). Values are the owner-correctable defaults; match the owner's Fantastical screenshots by eye.
- Remove every `.preferredColorScheme(.dark)` (10 sites). The Braun docs in `CLAUDE.md` "Theme/UI rules" are replaced, not appended.
- Build with `xcodebuild -scheme Stark -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`; verify by idb/simctl screenshots in BOTH appearances (`xcrun simctl ui booted appearance light|dark`).
- Dynamic Type must not clip the Add/Edit forms at the largest accessibility size.
- Ship step (controller only): full suite on merged main, device Release build, then `ios/App/ship.sh` (TestFlight only, never App Store review).

## Done when

- `cd ios && swift test` green (1094), `cd web && make test-fast` green, Release build for a device green.
- `grep -rn "preferredColorScheme(.dark)" ios/App` is empty; `grep -rn "Color(hex" ios/App/Stark/Stark` shows only `Theme.swift` and the two calendar-colour lines.
- Simulator screenshots in light AND dark of: agenda, Add (event and reminder), Edit, Apple detail, Settings, Apple settings, FAQ, Search, Weekly Review, month grid, year, planner (editable day) are readable (no white-on-white or black-on-black).
- TestFlight build uploaded (v2.0.25). Not part of done: the owner's device check; reported as not verified.

## Review Focus

- Text on `accent` fills (round Save button, KindSwitch selected segment, chips): contrast in both appearances.
- Anything that drew `Colors.background` as a "hole" over a card (planner blocks, month cells, selection fills) now sits on a grey ground; check selection states stay visible.
- Sheets/popovers (Add, Edit, Search, Settings, FAQ) previously forced dark; check the sheet's own background follows the token in both appearances.
- Keyboard sigil bar and tag suggestion row backgrounds in light mode.
- Dynamic Type at AX5 in Add/Edit.

---

### Task 1: Adaptive tokens and no forced dark

**Files:**
- Modify: `ios/App/Stark/Stark/Theme.swift` (Colors, plus a `Color(light:dark:)` helper)
- Modify: the 10 `.preferredColorScheme(.dark)` sites (AppleItemDetailView x2, EditItemView, ContentView, FAQView, SearchView, SettingsView, PlannerView x2, WeeklyReviewView): delete the modifier
- Modify: `ios/App/Stark/Stark/ContentView.swift` and any `UIWindow`/status-bar dark assumption found by grep

**Interfaces:**
- Produces: `Colors.card: Color`; every existing `Colors.*` token is now appearance-adaptive; `extension Color { init(light: UInt32, dark: UInt32) }` built on `UIColor { traits in ... }`.

- [ ] **Step 1:** Add the `Color(light:dark:)` helper and redefine the `Colors` tokens with the values in Global Constraints; add `Colors.card`. Update the file's header comment (Fantastical-style, no longer Braun).
- [ ] **Step 2:** Delete all ten `.preferredColorScheme(.dark)` modifiers; grep must come back empty.
- [ ] **Step 3:** Build for the simulator; launch in light and dark; screenshot agenda and Settings in each; fix any screen that renders unreadable at token level only (screen-specific restyling belongs to Tasks 3-5).
- [ ] **Step 4:** Commit `feat(app): adaptive light/dark tokens, follow the phone's appearance`.

### Task 2: System font behind `Fonts.mono`, drop JetBrains Mono

**Files:**
- Modify: `ios/App/Stark/Stark/Theme.swift` (`Fonts`)
- Delete: `ios/App/Stark/Stark/Fonts/` (JetBrainsMono-*.ttf, OFL.txt) and the `UIAppFonts` key in `ios/App/Info.plist`; update the pbxproj if the files are listed there

**Interfaces:**
- Produces: `Fonts.mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font` now returns `.system(size: size, weight: weight).monospacedDigit()` (name kept so 14 files need no edit; a rename is a later cleanup). `.semibold` maps to `.semibold`.

- [ ] **Step 1:** Re-implement `Fonts.mono` as above; build and screenshot the planner and month grid to confirm times and day numbers still align (monospaced digits).
- [ ] **Step 2:** Remove the font files and `UIAppFonts`; confirm no other reference (`grep -rn JetBrains ios`), clean build.
- [ ] **Step 3:** Commit `feat(app): system font replaces JetBrains Mono`.

### Task 3: Round buttons, KindSwitch, banners, keyboard bars

**Files:**
- Modify: `Theme.swift` (`SquareButton`, `SquareToolbarButton`, `SquareToolbarPlaceholder` keep their names and APIs), `KindSwitch.swift`, `SheetErrorBanner.swift`, `TagSuggestionRow.swift`, `SigilKeyboardBar.swift`, `ModeHandle.swift`

**Interfaces:**
- Consumes: Task 1 tokens.
- Produces: `SquareButton` renders a 40 pt `Circle` (fill `card` with a hairline shadow, or accent when prominent; disabled prominent drops to `card` with a dimmed glyph); on iOS 26 use `.glassEffect()` for the non-prominent one; `KindSwitch` a rounded segmented control (system `Picker(.segmented)` look, accent selection); banners rounded 12 pt cards.

- [ ] **Step 1:** Rework `SquareButton` (names unchanged, so toolbars keep compiling); verify the Add sheet's close/save buttons in both appearances.
- [ ] **Step 2:** Restyle `KindSwitch`, banners, tag suggestion row, sigil bar and mode handle to the tokens, rounded corners, system font.
- [ ] **Step 3:** Screenshots (light and dark) of Add event/reminder with a banner and keyboard bar shown; commit `feat(app): round buttons and Fantastical-style switch and banners`.

### Task 4: Forms and detail screens as grouped cards

**Files:**
- Modify: `AddItemView.swift`, `EditItemView.swift`, `CustomRepeatView.swift`, `RepeatPickerView.swift`, `RepeatEndPickerView.swift`, `OnDaysPickerView.swift`, `AppleItemDetailView.swift`

**Interfaces:**
- Consumes: Task 1-3 tokens/components.
- Produces: forms use `.listStyle(.insetGrouped)`, `.scrollContentBackground(.hidden)`, `.background(Colors.background)`, rows `listRowBackground(Colors.card)`; Delete becomes a full-width destructive row in its own section at the bottom (as in Fantastical); the Edit/Add toolbar keeps round buttons.

- [ ] **Step 1:** Convert Add and Edit to grouped cards (sections as in the owner's Fantastical Edit screenshot: title+location, all-day/starts/ends, calendar, repeat/alert, URL/notes, Delete); layouts of fields do not change.
- [ ] **Step 2:** Repeat pickers and Apple detail view the same way.
- [ ] **Step 3:** Screenshots light and dark at default and AX5 Dynamic Type for Add (both kinds), Edit, Apple detail; commit `feat(app): forms and detail as grouped cards`.

### Task 5: List and grid screens on the new tokens

**Files:**
- Modify: `AgendaView.swift`, `AgendaRow.swift`, `ContentView.swift`, `SearchView.swift`, `WeeklyReviewView.swift`, `MonthGridView.swift`, `YearView.swift`, `PlannerView.swift`, `PastDayView.swift`, `SettingsView.swift`, `AppleSettingsView.swift`, `ClaudeCodeSettingsView.swift`, `FAQView.swift`, `AccessRequiredView.swift`, `CalendarSidebar.swift`

**Interfaces:**
- Consumes: Tasks 1-4. Layouts, row targets (`AgendaRowTargets` sibling buttons) and gestures do not change.

- [ ] **Step 1:** Settings, Apple settings, Claude Code settings, FAQ, access screen as grouped cards (same pattern as Task 4).
- [ ] **Step 2:** Agenda, Search, Weekly Review, month, year, planner, past day: fix every spot where a token assumption broke (selection fills, hairlines, text on accent, planner blocks, dimmed event blocks); no layout changes. Replace hard-edged `Rectangle` backgrounds on chips/blocks with 8 pt rounded rectangles only where they are chrome (not the planner's time-accurate block edges).
- [ ] **Step 3:** Screenshots light and dark of every screen in "Done when"; commit per screen group.

### Task 6: Docs, full verification and the TestFlight build (controller)

**Files:**
- Modify: `CLAUDE.md` ("Theme/UI rules" paragraph rewritten; new "Fantastical redesign log" with Done / Not yet verified on device / Deferred), `README.md`, `docs/ios-feature-notes.md` if it mentions the look, spec status line

- [ ] **Step 1:** Update the docs; remove stale Braun/hard-edge/forced-dark statements (grep `Braun`, `hard edges`, `preferredColorScheme`).
- [ ] **Step 2:** `cd ios && swift test`, `cd web && make test-fast`, device Release build, the two greps from "Done when".
- [ ] **Step 3:** Merge to main locally, rerun the suite on the merged result, push main, `ios/App/ship.sh` (v2.0.25), log the upload in `CLAUDE.md`, vault session note.
