# Look Away

A tiny macOS menu bar app for the 20/20/20 rule: every 20 minutes of screen
time, look at something 20 feet away for 20 seconds.

## Behavior

- Lives in the menu bar (eye icon). No Dock icon, no main window.
- Every 20 minutes a floating panel appears on the display your cursor is on,
  above every other window, without taking keyboard focus from your current app.
- The panel starts a 20-second countdown the moment it appears. At zero it
  shows "Done", plays a soft chime, and closes itself.
- **Delay 5 min / Delay 10 min** hide the panel and bring it back later with a
  fresh 20-second countdown. Snoozes can be chained.
- **Decline** closes the panel immediately.
- The next 20-minute interval starts when the panel closes (finished or
  declined), never from a snooze.
- Sleep or screen lock pauses everything; wake or unlock starts a fresh
  20 minutes.
- Menu: live "Next break in m:ss", Pause / Resume Reminders, Take a Break Now,
  Launch at Login, Quit.

Durations live in `Sources/LookAwayCore/Config.swift`.

## Build and install

Requires Xcode 16 or newer (macOS 14+ target).

```bash
make install
```

That builds a release binary, wraps it in `Look Away.app`, ad-hoc signs it,
copies it to `/Applications`, and launches it. On its first launch from
`/Applications` it registers itself as a login item; toggle that from the menu.

Other targets:

| Command        | What it does                                   |
|----------------|------------------------------------------------|
| `make test`    | Runs the scheduler unit tests                  |
| `make run`     | Builds and launches from `./build` (dev loop)  |
| `make bundle`  | Builds the `.app` without launching            |
| `make clean`   | Removes build output                           |

## Layout

- `Sources/LookAwayCore` — pure Foundation: `Config`, the `Timekeeper` clock
  abstraction, and the `BreakScheduler` state machine.
- `Sources/LookAway` — AppKit/SwiftUI shell: menu bar item, floating panel,
  break view, sleep/lock observers, launch-at-login.
- `Tests/LookAwayCoreTests` — scheduler tests driven by a fake clock.
