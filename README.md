# Halfpast

A world clock that lives in the MacBook's notch (named for India's half-hour offset, which most clocks get wrong), modelled on the Omarchy *Timezones* plugin
(io.github.sspaeti.timezones) and worldtimebuddy.com, in Trilegal colours.

There is no menu bar icon. Rest the pointer on the notch and a black cap springs out of it
(a haptic click and a soft Tink) with two places either side of the camera — Bangalore and
Cleveland by default, each with a mark: teal dot at work, orange dot awake, moon asleep.
Move away and it folds back. Works over full-screen apps too.

Click the cap (or press **⌃⌥T** anywhere) and the glass ribbon drops out: one 24-hour strip
per place, columns on the same moment, working hours (8–18) in teal, an orange line for now,
the hour you pick in red, and the **fairest hour** outlined — the home hour that is least
unkind to the worst-off place (hours outside 8–18 count against a place; ties go to the
smallest total). Hover a column and every row's header shows that moment.

| Key | Action |
|---|---|
| 0–9 | start typing a time: `6:15 india`, `7:30am NY`, `18:00 london`, `9 cleveland`, `14.30 CET` |
| ← / → | nudge the proposed hour 5 minutes (⇧ for a whole hour; h / l also move an hour) |
| f | propose the fairest hour |
| [ / ] | previous / next day (‹ › and Today at the top left too) |
| d | meeting length: 15 → 30 → 45 → 60 minutes |
| n | back to now |
| t | 24-hour → AM/PM → 24-hour with a UTC row |
| p | copy the ribbon as a picture (selected column included) |
| c | copy the times as text |
| esc | close |

**Proposing a time.** Click an hour and a block the length of the meeting (15, 30, 45 or 60 minutes — the picker in the
bottom bar, or d; remembered as `meetingMinutes`) appears across every row. Nudge it
5 minutes at a time with ‹ 5 min › in the bottom bar or ← / →, or drag it (it snaps to 5
minutes): 6:10 covers 6:10–7:10 and slides into the next hour. You can also type a time — a time
and then a place (one of yours, any city or country, NY / SF, EST / IST / CET); no place means
home; without am/pm, 1–6 reads as the afternoon and 7–11 as the morning. Add a day anywhere —
today, tomorrow (tmrw), or a day name (tue, Friday); "next tue" skips today. The day is that
place's date ("9pm SF mon" is Tuesday morning in Bangalore) and the grid moves to it. The bar shows the start
in every place; **Copy for email** puts each place's hour, start to end, with its abbreviation
and date on the clipboard (with nothing proposed, the fairest hour). × or n clears it. Without a day, a
typed time falls on the day the grid shows. Clicks and drags on the grid are handled in
AppDelegate.gridMouse, not SwiftUI gestures, so the first click counts in the non-activating panel.

**Hiding a place for now.** Hover a place and click the eye: its row folds to a thin line and it
drops out of the email and the fairest hour. Click the line to bring it back. Hiding isn't saved
— it lasts until you show the place again or quit.

**Places & appearance** (the gear at the bottom right of the ribbon, `s`, or right-click the cap)
swaps the ribbon for settings in the same glass panel: rename, reorder or remove places, and add a place by searching ~150 cities (offline, other names like
Bengaluru work), every zone macOS knows, or — only when asked — Apple Maps. Six places at most,
home included: more than that crowds the ribbon. Appearance is Light, Dark or Match Mac (live).
Changes save to places.json at once.

**Favourites and home.** A star marks a favourite: two at most, shown either side of the notch.
A house appears only on starred places and is filled on the one that is home — the top row, the
left of the notch, and the clock everything is measured from (columns, "+2:30", the fairest
hour). Click the other favourite's outline house to swap; star a third place and it replaces the
second favourite. Home can't be unstarred or removed. A place with `"zone": ""` (Bangalore)
follows the Mac's time zone whether or not it is home.

Right-click the cap for Places & appearance and Quit. Scripts can post the distributed
notifications `com.rahulmatthan.halfpast.toggle` and `com.rahulmatthan.halfpast.settings`.

Without a notch (lid closed on an external display) a notch-sized spot at the top centre of the
main screen does the same job.

## Places

`~/Library/Application Support/Halfpast/places.json` (created on first run; written by Places & appearance; an older `~/.config/zones/places.json` is adopted once).
`"zone": ""` with `"home": true` follows the Mac's own time zone. When the Mac is
set to a zone not in `homeHalfpast`, the home row is relabelled with where the
clock actually is. `abbr` overrides the tzdata abbreviation (tzdata calls
Singapore "+08"). `favourites` names the two places beside the camera, home first; `clickSound: false`
keeps the haptic but drops the Tink. Summer time comes from macOS's own time zone data, so it is
always correct without a network.

## Build, install, distribute

- `./build.sh` — universal app (Apple silicon + Intel) with swiftc, no Xcode; Hanken Grotesk is
  bundled (Resources/Fonts, SIL OFL) and registered at launch; the icon is drawn by
  `scripts/make-icon.swift` (delete Resources/AppIcon.icns to redraw).
- `./install.sh` — this Mac: ~/Applications/Halfpast.app, then opens it.
- `./build-dmg.sh` — `dist/Halfpast-<version>.dmg` for anyone: Developer ID signature with the
  hardened runtime, a drag-to-Applications image, then notarisation and stapling when the
  keychain profile `notary` exists (see the top of the script).
- First run: a welcome drops from the notch, and the app registers itself as a login item
  (SMAppService; switch in Places & appearance).
- `docs/` — the website (index.html, screenshots in img/). The download link expects
  `docs/Halfpast-1.0.dmg` next to it.

Screenshots: `HALFPAST_SNAPSHOT=x.png [HALFPAST_TIME="7:30am NY tue"] [HALFPAST_LIGHT=1]`,
`HALFPAST_SETTINGS=x.png [HALFPAST_FIVE=1 HALFPAST_QUERY=Tok]`, `HALFPAST_WELCOME=x.png`,
`HALFPAST_NOTCH=x.png` on build/Halfpast.app/Contents/MacOS/Halfpast — they render and quit
without changing settings.
