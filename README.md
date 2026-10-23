# Halfpast

A world clock that lives in the MacBook's notch (named for India's half-hour offset, which most clocks get wrong), modelled on the Omarchy *Timezones* plugin
(io.github.sspaeti.timezones) and worldtimebuddy.com, in Trilegal colours.

There is no menu bar icon. Rest the pointer on the notch and a black cap springs out of it
(a haptic click and a soft Tink) with two places either side of the camera — Bangalore and
Cleveland by default, each with a mark: teal dot at work, orange dot awake, moon asleep.
Move away and it folds back. Works over full-screen apps too.

Click the cap (or press **⌃⌥T** anywhere) and the glass ribbon drops out: one 24-hour strip
per place, columns on the same moment, each place's working hours in teal (holidays in a warm orange), an orange line for now,
the hour you pick in red, and the **fairest hour** outlined — the home hour that is least
unkind to the worst-off place (each hour outside a place's working hours counts against it, a
weekend or holiday there four more; ties go to the smallest total). Hover a column and every row's header shows that moment.

| Key | Action |
|---|---|
| 0–9 | start typing a time: `6:15 india`, `7:30am NY`, `18:00 london`, `9 cleveland`, `14.30 CET` |
| ← / → | nudge the proposed hour 5 minutes (⇧ for a whole hour; h / l also move an hour) |
| f | propose the fairest hour |
| [ / ] | previous / next day (‹ › and Today at the top left too) |
| d | meeting length: 15 → 30 → 45 → 60 minutes |
| n | back to now |
| t | 24-hour → AM/PM → 24-hour with a UTC row |
| u | check for updates (or install the one waiting) |
| ⌘Q | quit |
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

**Every place on its own clock.** Each row's cells are that place's own hours. Where its clock is
off home's by half an hour (or 45 minutes), its cells sit that far off home's columns — on
Bangalore time, Singapore's 10 straddles Bangalore's 7 and 8, and Bangalore's 8 lands in the
middle of it (10:30). Each strip also runs on past the day — real hours of yesterday and tomorrow, numbers
and all — for `Metrics.bleed` either side, dissolving to nothing, so no row has an end. Columns, hover, clicks, the fairest hour, the now line and the
proposed block stay on home's hours and cut straight through (`RibbonPanel.strip`).

**Keep now in the middle** (switch at the top of Places & appearance, `rolling` in places.json,
off by default): the ribbon shows twelve hours either side of now and drifts left as time passes
— `dayStart` is home's hour twelve hours ago and every grid layer is drawn `Store.scroll`
columns to the left; the 23 whole columns are `Store.columns`. The fairest hour is the best of
the next 24 hours (if it's past the right edge the bar names its day, and f goes there), and a
typed time without a day means the next time it comes round.

**Working week and holidays.** The calendar button on each place in Places & appearance opens
its working week on the right: hours (half-hour steps, default 8–18), working days (default the
country's usual week — Sun–Thu in Saudi Arabia, Qatar, Kuwait, Bahrain, Oman, Egypt, Jordan,
Israel…; Mon–Fri elsewhere), public holidays on or off, and days off of its own (an office
closure, someone's leave). The grid colours a holiday's working hours orange and a weekend's as
merely awake; the row header names the day ("Dussehra", "Sunday"); the bottom bar warns when
the proposed (or fairest) time falls on one ("Thanksgiving Day in Cleveland"). Regional
holidays ("Easter Monday" in England, Wales and Northern Ireland only) show as "Easter
Monday?" and count only lightly. Holidays come from Google Calendar's public holiday calendars
(`en.<country>#holiday@group.v.calendar.google.com`, no key or account; only the country is
sent), are cached in `~/Library/Application Support/Halfpast/Holidays/<CC>.json` and refreshed
monthly. The country comes from the place's time zone (macOS's zone.tab). Stored per place in
places.json as `work` [start, end], `workdays` (1 = Sunday), `holidays: false`, `daysOff`
["yyyy-MM-dd"] — absent means the default.

**Travel.** When the Mac's time zone moves somewhere with a different clock from home, the
places that follow the Mac (`"zone": ""`) stay on home's zone, and the ribbon's hint line asks
"This Mac is on London time — Plan from London / Keep Bangalore". Planning from London makes
London the top row and the clock everything is measured from (one of your places if it is on
that zone, else a row of its own), with home kept below; the notch still shows your two
favourites. The answer is saved as `travel` and cleared when the Mac is back on home's zone.

**Updates.** Sparkle (2.10, in `vendor/`, fetched and checksum-checked by build.sh) checks
https://exmachina.in/halfpast/appcast.xml once a day and offers a new version; right-click the
cap › Check for Updates…, `u` in the ribbon, or "Check for updates" at the bottom of Places &
appearance does it now (the right-click menu can be swallowed by a menu bar manager like Ice).
A version found in the background doesn't pop up an alert — Halfpast has no Dock icon, so it
would open unseen behind other apps. Instead (Sparkle's "gentle reminders",
`SPUStandardUserDriverDelegate` in App.swift) a small arrow appears on the notch and an
"Update to 1.x" button in the ribbon; the alert opens when he clicks it. Updates are verified with the EdDSA key in Info.plist
(`SUPublicEDKey`) — see RELEASING.md.

Right-click the cap for Places & appearance, Check for Updates and Quit — also at the bottom of
Places & appearance, and `u` / ⌘Q in the ribbon. Scripts can post the distributed
notifications `com.rahulmatthan.halfpast.toggle` and `com.rahulmatthan.halfpast.settings`.

Without a notch (a MacBook Air M1 or older, or the lid closed on an external display) a
notch-sized spot at the top centre of the main screen does the same job: the black cap grows
out of the menu bar there. Runs on macOS 13 Ventura or later (1.0–1.2.1 needed 15).

## Places

`~/Library/Application Support/Halfpast/places.json` (created on first run; written by Places & appearance; an older `~/.config/zones/places.json` is adopted once).
`"zone": ""` with `"home": true` follows the Mac's own time zone, while it is in `homeZones`
(the zone it was set up in); elsewhere it stays on home's zone (see Travel). `abbr` overrides the tzdata abbreviation (tzdata calls
Singapore "+08"). `favourites` names the two places beside the camera, home first; `clickSound: false`
keeps the haptic but drops the Tink. Summer time comes from macOS's own time zone data, so it is
always correct without a network.

## Build, install, distribute

Releasing a new version, and how signing and notarisation are set up: **RELEASING.md**.

- `./build.sh` — universal app (Apple silicon + Intel) with swiftc, no Xcode; Hanken Grotesk is
  bundled (Resources/Fonts, SIL OFL) and registered at launch; the icon is drawn by
  `scripts/make-icon.swift` (delete Resources/AppIcon.icns to redraw).
- `./install.sh` — this Mac: ~/Applications/Halfpast.app, then opens it.
- `./build-dmg.sh` — `dist/Halfpast-<version>.dmg` for anyone: Developer ID signature with the
  hardened runtime, a drag-to-Applications image, then notarisation and stapling when the
  keychain profile `notary` exists (see the top of the script).
- First run: a welcome drops from the notch, and the app registers itself as a login item
  (SMAppService; switch in Places & appearance).
- `docs/` — the website (index.html, screenshots in img/) and `appcast.xml`, the update feed
  (written by build-dmg.sh). Downloads and updates come from the GitHub release `v<version>`,
  so GitHub counts them (`gh release view v<version> --json assets`).

Screenshots: `HALFPAST_SNAPSHOT=x.png [HALFPAST_TIME="7:30am NY tue"] [HALFPAST_LIGHT=1]`,
`HALFPAST_SETTINGS=x.png [HALFPAST_FIVE=1 HALFPAST_QUERY=Tok]`, `HALFPAST_WELCOME=x.png`,
`HALFPAST_NOTCH=x.png` on build/Halfpast.app/Contents/MacOS/Halfpast — they render and quit
without changing settings (Config.save does nothing in snapshot mode). `HALFPAST_EDIT=<index>`
opens a place's working week in the settings shot; `TZ=Europe/London HALFPAST_TRAVEL=ask|here|home`
shows travel.

## Licence

MIT — see LICENSE. The bundled typeface, Hanken Grotesk, is under the SIL Open Font License
(Resources/Fonts/OFL.txt).
