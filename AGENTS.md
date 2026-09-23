# AGENTS.md

Guidance for coding agents working in this repository lives in [CLAUDE.md](CLAUDE.md). Read it first.

Short version:

- The product is the native Swift app in `ios/`. All testable logic goes in `ios/Sources/StarkKit`; the SwiftUI views in `ios/App/Stark` stay thin.
- `mobile/` (Expo) and `shared/` (its todo.txt logic) are deprecated. Do not change them unless explicitly asked.
- There is no command-line app and no iCloud storage, and neither is planned.
- Test with `cd ios && swift test`. Deploy to a connected iPhone with `ios/App/deploy.sh`.
