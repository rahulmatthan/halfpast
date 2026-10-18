# Halfpast — a world clock in the Mac's notch

A native SwiftUI/AppKit app, built with swiftc (no Xcode) like ~/Coding/vitals and ~/Coding/stow.
No menu bar icon: rest the pointer on the notch and a black cap springs out with two places;
click it (or ⌃⌥T) and a glass "ribbon" drops down — one 24-hour strip per place, the fairest
hour, a proposed meeting you can nudge and copy for email. Public, MIT, released at
https://exmachina.in/halfpast/. README.md is the user-facing description; RELEASING.md is how to
ship a version and how signing/notarisation work. Read RELEASING.md before any release.

Built 18 Oct 2026 as "Zones" (a port of the Omarchy Timezones plugin, io.github.sspaeti.timezones),
then redesigned and renamed Halfpast — a nod to India's half-hour offset.

## Sources

- `App.swift` — AppDelegate: the notch cap window and the panel (both borderless, non-activating
  `KeyPanel`s at status-bar level, on all Spaces and over full-screen apps); a 25 Hz pointer
  poll that opens the cap after ~0.12 s on the notch and folds it ~0.3 s after leaving;
  `gridMouse` (clicks and drags on the grid, done in AppKit — see below); keys; copying;
  the `HALFPAST_*` screenshot mode; first-run welcome and login item.
- `Notch.swift` — `NotchUI` (shared animation state), `NotchShape` (flared shoulders, rounded
  bottom), `NotchView` (the cap and its two "ears": teal dot at work, orange awake, moon asleep).
- `Ribbon.swift` — `Palette` (dark navy glass / light pale glass; Trilegal ribbon colours),
  `PanelChrome` (glass, edge, ribbon stripe), `Metrics` (all grid geometry; `Metrics.x(hours)`
  maps a moment across cells and gaps), `RibbonPanel` (rows, hidden rows, fairest outline,
  now line, proposal block, bottom bar with duration picker, nudges, Copy for email).
- `Settings.swift` — Places & appearance in the same panel: star = favourite (two, beside the
  notch), house = home (one of the favourites; first row; the clock everything is measured
  from), rename/reorder/remove, city search, Light/Dark/Match Mac, Open at login.
- `Model.swift` — `Config` (places.json; every key optional so old files load; `tidied()`
  enforces one home, first, among ≤2 favourites), `Row`, `Store` (rows, fairest hour, proposal
  as a 5-minute-snapped block of `duration` minutes, `dayOffset`, hidden places, text for email).
- `TimeParser.swift` — "6:15 india", "7:30am NY tue", "next fri 9 london": time, then place
  (his places, abbreviations like EST/IST/CET, curated cities, zone list); day words anywhere.
  No am/pm: 1–6 → afternoon, 7–11 → morning.
- `Cities.swift` — ~150 curated cities (with short codes and other names) + every macOS zone;
  Apple Maps (CLGeocoder) only when the user clicks "look up".
- `Welcome.swift` — first-run welcome; `LoginItem` (SMAppService).
- `Hotkey.swift` — Carbon RegisterEventHotKey (no Accessibility permission), from ~/Coding/orc-app.
- `Holidays.swift` — `Holiday`, `DayOff` (weekend / holiday / own day / regional), `Country`
  (zone → country from /usr/share/zoneinfo/zone.tab; usual working days), `Holidays` (Google
  Calendar public holiday .ics per country, cached monthly in Application Support/Halfpast/Holidays).

1.1 (Oct 2026) added per-place working weeks and holidays (`Store.dayOff`, `Store.phase`,
`offNotes`; the editor is `SettingsView.week`), travel (`Store.away`, `planningHere`,
`planRows` — the ribbon's rows; `places` stays indexed like places.json, which Settings relies
on), and Sparkle updates (vendor/, `SPUStandardUpdaterController` in AppDelegate).

Settings: `~/Library/Application Support/Halfpast/places.json` (the old ~/.config/zones file is
adopted once). Bundle id `com.rahulmatthan.halfpast`. Distributed notifications
`com.rahulmatthan.halfpast.toggle` / `.settings` open the panel from scripts.

## Things that bit

- **Clicks in a non-activating panel.** SwiftUI tap gestures on the grid were unreliable (and a
  click looked like a hover); grid clicks/drags go through `gridMouse`, a local AppKit monitor.
  Hosting views use `FirstClickHostingView` (acceptsFirstMouse).
- **Keys** go through a local keyDown monitor while the panel is visible; when a text field is
  active (typing a time, settings) the monitor must hand keys to the field — check the
  `timeQuery`, `settingsShown` and `welcomeShown` branches in `handleKey` when adding keys.
- **ImageRenderer** can't draw text fields, switches or NSVisualEffectView: `snapshotMode`
  swaps in plain text and fills. Screenshot runs must not save settings (a `defer` doesn't run
  because the app terminates — restore explicitly).
- **Foundation abbreviations** are "GMT+5:30"; `tzAbbreviation` reads tzdata's (IST, BST) and
  Singapore is overridden to SGT.
- **Fonts**: Hanken Grotesk is bundled and registered at launch (CTFontManager, process scope);
  without that other Macs fall back to the system font.
- **Snapshots and settings**: `Config.save` does nothing in snapshot mode — a 1.1 screenshot run
  once saved a test `travel` into his file through an unrelated `change()`.
- **Sparkle signing**: build-dmg.sh signs Autoupdate, Updater.app, the framework, then the app,
  each with the hardened runtime (XPC services are removed in build.sh — not sandboxed).
- `NSStatusBar`/notch geometry: `auxiliaryTopLeftArea`/`RightArea` give the camera housing;
  no notch → a 184-pt spot at the top centre of the main screen.

## Testing

Claude can't send clicks or keystrokes here (no Accessibility permission for Terminal), so:
render panels with the `HALFPAST_*` variables (README), toggle the live panel by posting the
distributed notifications and `screencapture -R` the top of the screen, move the pointer with
`CGWarpMouseCursorPosition` to test the hover, and exercise `Store`/`TimeParser` from a small
swiftc harness — back up places.json first and confirm it is unchanged afterwards. Say plainly
which interactions were not tested live.
