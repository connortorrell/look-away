# Mine Away

A tiny macOS menu bar app for the Minecraft 20/20/20 rule: every 20 minutes —
one full Minecraft day — look 20 blocks away for 20 seconds, so the Enderman
does not aggro.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/popup-dark.png">
    <img src="docs/popup-light.png" alt="Mine Away night popup showing a 20-second countdown with Sleep and Make Eye Contact buttons" width="560">
  </picture>
</p>

## Why this was always a Minecraft app

Endermen aggro when you look at them. That is the entire mechanic, and it is
the entire app: something appears on screen, and the correct response is to
look somewhere else for a bit.

The timings were already right, which is the part worth sitting with:

| Look Away        | Minecraft                          |
|------------------|------------------------------------|
| 20 minutes       | 24000 ticks — one full day-night cycle |
| 20 seconds       | 400 ticks                          |
| 5 minute delay   | 6000 ticks — a quarter day, a night's sleep |
| 20 feet          | 20 blocks (a block is roughly a metre; close enough) |

Not one duration changed in this PR. `Config.standard` produces the same
intervals it produced in 1.0. They simply have correct names now, in
`Sources/LookAwayCore/MinecraftTime.swift`.

## Behavior

- Lives in the menu bar (block icon). No Dock icon, no main window.
- Every 24000 ticks the sun goes down: a floating panel appears on the display
  your cursor is on, above every other window, without taking keyboard focus
  from your current app.
- The panel starts a 400 tick countdown the moment night falls. At zero it
  shows "Done", plays the closest thing macOS ships to an XP orb, and closes
  itself.
- **Sleep (6000 ticks)** hides the panel and brings it back at the next sunset
  with a fresh 400 tick countdown. Sleeping can be chained, which is not how
  beds work, but is how this works.
- **Make Eye Contact** closes the panel immediately and accepts what follows.
- The next cycle starts when the panel closes (finished or declined), never
  from a sleep.
- Sleep or screen lock pauses everything; wake or unlock starts a fresh day at
  sunrise. Raids hold the cycle the same way, if you switch that on.
- Menu: live "Sunset in m:ss (n ticks)", Switch to Peaceful / Leave Peaceful
  Mode, Skip to Night, Launch at Login, Settings, Quit.

Durations live in `Sources/LookAwayCore/Config.swift`. Tick math lives in
`Sources/LookAwayCore/MinecraftTime.swift`.

## Ticks

Every countdown in the app now reads `4:32 (5,440 ticks)`. Minutes and seconds
are kept in the parentheses for people who have not yet made the adjustment.
The plan is to drop them in 2.0.

`MinecraftTime` exposes the cycle boundaries as well, so the menu bar knows
which phase you are in:

| Ticks         | Phase   | Hostile mobs |
|---------------|---------|--------------|
| 0–11999       | Day     | no           |
| 12000–12999   | Sunset  | no           |
| 13000–22999   | Night   | **yes**      |
| 23000–23999   | Sunrise | no           |

## Schedule

**Settings…** in the menu opens a schedule panel. It is opt-in: leave it off
and the sun rises and sets around the clock, exactly as before.

<p align="center">
  <img src="docs/settings.png" alt="Mine Away settings panel with the schedule switched on, Monday through Friday selected, default hours of 8:00 AM to 5:00 PM, and Monday customized to end at 3:00 PM" width="470">
</p>

- Click the S M T W T F S circles to pick the days the cycle should run on.
- One start and end time covers every selected day — set 9:00 AM to 5:00 PM
  once and the whole week follows it.
- Need an exception? **Different hours on some days** reveals a row per
  selected day where any one of them can be given its own start and end. Days
  with their own hours get a dot under their circle; **Reset** puts them back
  on the shared hours.
- An end time earlier than the start reads as overnight, so 10:00 PM to 2:00 AM
  works for a night shift; the panel marks it "(next day)".
- Outside the schedule the menu bar shows a moon and the menu reads "Spawn
  chunks unloaded — back Mon at 9:00 AM". **Skip to Night** still works.

## Raids

The same panel can hold the cycle while you're on a call, which this app now
calls a raid, because that is what they are. Also opt-in: leave **Pause the
cycle during raids** off and nothing is watched at all.

- **Apps that count as a raid** is a list of chips over a search field. Type to
  search every app installed on the Mac and click one to add it. The first time
  the panel opens, the raid apps you actually have installed — Zoom, Teams,
  Slack, Pop, Discord, FaceTime, Webex and the browsers — are filled in for you.
- Detection watches **real device use, not which app is in front**: macOS is
  asked which processes are holding an input stream, so a Zoom window sitting
  in the background during a raid still counts, and Zoom merely being open does
  not. Neither query records anything, so neither one asks for microphone or
  camera permission.
- **Bell delay** is how long the microphone has to stay busy before the bell
  rings, so a notification chime doesn't summon a raid. Once a raid is on, a
  30-second grace period covers a spell on mute.
- **The cycle keeps running through a raid.** Only the popup is held back, so
  time on the call still counts towards nightfall. A night that came due during
  a raid falls the moment the bell stops — which is when you most want it,
  after an hour of staring at faces.
- While a raid is on, the menu bar shows a bell and the menu reads "Zoom raid —
  sunset in 4:32 (5,440 ticks)".

## Install

There is no prebuilt download. You build the app yourself, which takes about a
minute — three ticks short of a Minecraft hour — and needs two things:

- macOS 14 Sonoma or newer.
- Xcode 16 or newer, installed from the Mac App Store and opened once so it can
  finish setting up its command line tools.

Then, in Terminal:

```bash
git clone https://github.com/connortorrell/look-away.git
cd look-away
make install
```

`make install` does everything: it compiles the app, wraps it into
`Mine Away.app`, signs it for local use, copies it to your `Applications`
folder, and launches it.

When it's running you'll see a block in the menu bar. Click it to see the time
until sunset, switch to Peaceful, or skip straight to night. The first night
falls 24000 ticks after launch.

### Updating

```bash
cd look-away
git pull
make install
```

### Uninstalling

Quit Mine Away from its menu, then drag `Mine Away.app` out of `Applications`
to the Trash.

### Other make targets

| Command        | What it does                                   |
|----------------|------------------------------------------------|
| `make test`    | Runs the scheduler and tick-math unit tests    |
| `make run`     | Builds and launches from `./build` (dev loop)  |
| `make bundle`  | Builds the `.app` without launching            |
| `make clean`   | Removes build output                           |

## Layout

- `Sources/LookAwayCore` — pure Foundation: `MinecraftTime`, `Config`, the
  `Timekeeper` clock abstraction, the `Schedule` and `MeetingSettings` models
  and their storage, the raid-detection debounce, and the `BreakScheduler`
  state machine.
- `Sources/LookAway` — AppKit/SwiftUI shell: menu bar item, floating panel,
  night view, settings panel, the CoreAudio/CoreMediaIO activity probe and the
  installed-apps scan, sleep/lock observers, launch-at-login.
- `Tests/LookAwayCoreTests` — scheduler, schedule, raid-detection and tick-math
  tests, driven by a fake clock and a fake device probe.

## Not in this PR

- Renaming the `LookAwayCore` module to `MineAwayCore`. The bundle identifier
  is deliberately unchanged too, so existing preferences migrate cleanly.
- Hardcore mode, where **Make Eye Contact** quits the app and deletes the
  preferences.
