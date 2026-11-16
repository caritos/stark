# Stark visual redesign: Fantastical look (staged)

Date: 2026-11-15. Status: awaiting owner approval. Tracks GitHub issue #120.

## Intent and why

The owner wants Stark to be "pretty much a duplicate of the Fantastical app" (Apple Calendar and Reminders are the data; Stark is the better view plus the Claude Code workflow). On 2026-11-15 the owner decided to leave the dark Braun/Bauhaus look for Fantastical's look: light by default, system font, white rounded cards on a light grey ground, blue accent, round glass buttons, and Fantastical's layouts (week ticker, month, timeline). Reference: the owner's Fantastical screenshots (event detail and edit screens received; main day/agenda, month and week/day screens still to come).

## Goals

- Stark reads as Fantastical at a glance on every screen, in light and dark appearance (follows the phone).
- Every stage ships to TestFlight so the owner reacts to real screens before the next stage.
- No behaviour changes: data, write path, tests keep working unchanged.

## Non-goals / anti-goals

- No new features inside the redesign (natural-language quick add, widgets, weather etc. stay on #120).
- No copying of Fantastical's assets, icon or trademarks; we reproduce layout conventions only.
- Not a failure if some screens still look old between stages, but a mixed state must stay readable (no unreadable text on the wrong ground).

## Constraints

- The owner is the only user; staged TestFlight builds are authorised. No App Store submission.
- Colors only through `Theme.swift` tokens; no hardcoded hex or `Color.white/black` in views (assets or semantic system colors).
- TDD does not apply to pure styling; anything with logic (week ticker selection, date math) goes in StarkKit with tests first. Verify visuals on the simulator with screenshots, and on device via TestFlight.
- Light and dark both checked for each stage (Xcode simulator appearance toggle, idb screenshots).
- Accessibility: Dynamic Type must not clip; contrast of text on cards at least AA.

## Approaches considered

1. One big restyle branch: fastest on paper, no feedback until the end, one large change to unpick. Rejected.
2. **Staged, each stage shipped (chosen by the owner).**
3. Rebuild each screen from scratch: closest match but discards tested view code. Rejected.

## Stages

**Stage 1, foundation (this plan, detailed)**
- `Colors` becomes adaptive semantic tokens (light and dark variants): grouped background (light grey ground), card (white), text, textSecondary, separator, accent (system-like blue), plus a calendar-colour passthrough for events. Keep `eventDot` purple only until stages 2-3 replace the markers with Apple calendar colours.
- Remove all ten `.preferredColorScheme(.dark)` forcings so the app follows the phone.
- `Fonts.mono` call sites move to the system font (keep monospaced digits where alignment needs them). JetBrains Mono files and `UIAppFonts` are dropped once no caller remains.
- `SquareToolbarButton`/`SquareButton` become round glass-style buttons (circle, system material on iOS 26, plain circle on older), same API so call sites do not change.
- `KindSwitch`, `SheetErrorBanner`, `TagSuggestionRow`, `SigilKeyboardBar`, `AccessRequiredView`, FAQ, Settings screens restyled to cards on the grouped ground.
- Agenda and planner screens get the new tokens and fonts only; their layouts do not change in this stage.
- Docs: CLAUDE.md "Theme/UI rules" paragraph and README screenshots note updated; website screenshots later (stage 5).

**Stage 2, agenda (outline)**: Fantastical's top section (week ticker with month calendar toggle), day headers, event rows with calendar-colour bars and time columns, reminder rows with round checkboxes. Needs the owner's main-screen screenshots first. Selection and date logic in StarkKit with tests.

**Stage 3, month and year views (outline)**: Fantastical's month grid with event titles/colour chips; year view restyle. Replace purple density dots.

**Stage 4, planner (outline)**: day timeline and plan blocks in the new language; largest piece (77 theme references in `PlannerView`), split `PlannerView.swift` as part of it (already wanted).

**Stage 5, polish (outline)**: Apple detail view, Settings, FAQ copy, App icon decision, website screenshots and copy (privacy/FAQ unaffected), CLAUDE.md log.

## Done when (stage 1)

- `cd ios && swift test` green; `make test-fast` green; Release build for a device green.
- Simulator screenshots (light and dark) of agenda, Add, Edit, Apple detail, Settings, FAQ, Search, Weekly Review, planner and month grid are readable, with no forced-dark leftovers and no white-on-white or black-on-black text.
- No `preferredColorScheme(.dark)` and no `Color(hex:)` outside `Theme.swift` (grep).
- TestFlight build uploaded; owner device check is NOT part of done, reported as not verified.

## Left to the builder

Exact blue and grey values (match Fantastical screenshots by eye: ground about #F2F2F7, card white, accent about #3B82F6, check against the owner's screenshots), how to map each `Colors` use to a token, and the round-button material fallback for iOS 17.
