# Website: light restyle and import copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make stark.caritos.com look like the app (light, blue accent, system font, white cards, dark mode via the phone setting) and make `privacy.html` true after the import.

**Architecture:** Static pages in `web/public/pages/*.html` embedded by the Go binary; all colours live in `web/public/static/style.css` (96 lines), so the restyle is mostly CSS plus small markup hooks. `web/api/embed/` is generated and gitignored: never edit it.

**Tech Stack:** static HTML/CSS, Go tests (`web/api/internal/web/web_test.go`), Playwright (`web/test/e2e/site.spec.ts`), Node 24 + pnpm via corepack.

**Spec:** the owner's approval in conversation 2026-11-17: restyle the site to match the app, keep page structure and copy, reword the privacy line about local items, show screenshots BEFORE any deploy. No deploy in this plan.

## Global Constraints

- Node 24 from `web/.nvmrc`, same shell as the tests (`source ~/.nvm/nvm.sh && cd web && nvm use`; no pipe on the nvm line). pnpm via corepack. Never npm/yarn.
- Every page keeps lotus's `site-footer` with `Build @@BUILD_ID@@` exactly once; contact `support@caritos.com`; no page links to `/app/`; trailing-slash 301s and the 404 page behave as before (tests pin these). Do not change copy except `privacy.html` DATA STORAGE (below) and anything the new look needs.
- App tokens to match (from `ios/App/Stark/Stark/Theme.swift`): background light `#F2F2F7` / dark `#000000`; card `#FFFFFF` / `#1C1C1E`; accent `#3B82F6` / `#5B9BFF`; text `#1C1C1E` / `#F2F2F7`; secondary text `#8E8E93`; separator `#D1D1D6` / `#38383A`; year/header red `#FF3B30` / `#FF453A`. Use CSS custom properties on `:root` and override in `@media (prefers-color-scheme: dark)`; give `html` and `body` an explicit background. Body font is the system stack (`-apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif`), no monospace except `code`.
- Contrast: body text and links must meet WCAG AA on both backgrounds (check the muted grey on `#F2F2F7`; if `#8E8E93` fails for body copy use a darker grey for paragraphs and keep it for small labels).
- Layout works at 390 px and 1280 px with no horizontal page scroll (the screenshot strip scrolls inside itself). Hit targets of footer links at least 44 px tall on phones.
- Commit trailers: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01D4JSV4Qz5xEkCxoor2D9h7`.

## Done when

- `cd web && make test-fast` and `make e2e` (after `make e2e-install` if needed) green, plus `make build` and `web/scripts/smoke.sh` against the local binary as `web/docs/testing.md` describes (use `SMOKE_APP=0`).
- Screenshots of all five pages (`/`, `/faq`, `/privacy`, `/terms`, `/support`) read and checked at 1280 px and 390 px, in light AND dark (headless Chromium via Playwright with `colorScheme` set), saved under `/private/tmp/claude-501/site-shots/`; no cropped text, no overflow, the screenshot strip looks right on both backgrounds.
- `TestPrivacyDatedAndMentionsData` updated with the new wording and passing.
- NOT part of done: deploying (the owner decides after seeing the screenshots), the stark/ `.superpowers` ledger, the in-app FAQ.

## Review Focus

- Dark mode contrast of the muted grey and of links.
- The long unbroken strings (the support address, `code`) at 390 px.
- The 404 page and the generated "not found" markup, which use `main` and `code` without a header.

---

### Task 1: privacy wording (test first)

**Files:** Modify `web/public/pages/privacy.html` (DATA STORAGE, the first paragraph, ~line 30), `web/api/internal/web/web_test.go` (`TestPrivacyDatedAndMentionsData`).

- [ ] **Step 1: Update the test first** so it asserts the new facts and forbids the stale ones: it must contain "once" and "Stark's own items" (the Settings entry) and "backup", and must NOT contain "still shows them and lets you change them". Run `cd web && make test-fast` (Node 24): FAIL for the right reason.
- [ ] **Step 2: Replace** the paragraph with exactly: "Items Stark created before it saved to Apple Calendar and Reminders may still be stored in files inside Stark's private storage on your device. Stark can copy them into Apple Calendar and Reminders once (Settings, Stark's own items); after that Stark hides its own copies and keeps the old files on your device only as a backup, and it deletes nothing. Stark does not use iCloud for these files and does not sync them between devices." Keep the page's "Updated" date line consistent with `TestPrivacyDatedAndMentionsData` (the date is now NOVEMBER 2026 already; leave it unless the test requires a change).
- [ ] **Step 3: Run** `make test-fast`: PASS. Commit `web: privacy copy describes the one-time import`.

### Task 2: light and dark stylesheet

**Files:** Modify `web/public/static/style.css`; touch `web/public/pages/*.html` only for hooks the design needs (for example a `.card` wrapper class on the contact block, an `h2` style change); update `web/test/e2e/site.spec.ts` only if a selector must change (keep every behaviour assertion).

- [ ] **Step 1: Rewrite** `style.css` with the tokens above: `:root` light values, `@media (prefers-color-scheme: dark) { :root { ... } }`; header with the STARK wordmark in the accent colour (letter-spaced small caps kept), h1 in text colour, `h2` section labels in accent, paragraphs in the readable grey, `.contact-block` and `code` as white/dark cards with a separator border and 12 px radius, the App Store badge unchanged, screenshot strip with rounded 20 px image corners and a soft border, footer links in secondary text turning accent on hover/focus with a visible `:focus-visible` outline in the accent. Remove the Braun wording from the file's comment.
- [ ] **Step 2: Build and look:** `cd web && make build`, run `web/dist/stark` locally (see `web/docs/testing.md` for env such as `ADDR`, `DATA_DIR`) and capture the screenshots listed in Done when with a small Playwright script kept OUTSIDE the repo (in `/private/tmp/claude-501/`). Read every screenshot; fix what you see.
- [ ] **Step 3: Run** `make test-fast`, `make e2e`, `make build`, smoke script: PASS. Report each.
- [ ] **Step 4: Commit** `web: light and dark restyle to match the app`.
