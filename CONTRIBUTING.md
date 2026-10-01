# Contributing

## Building from source

You need Xcode 16 or newer. Install it from the Mac App Store and open it once
so it can finish setting up its command line tools. Then:

```bash
git clone https://github.com/connortorrell/look-away.git
cd look-away
make install
```

`make install` builds the app, wraps it into `Look Away.app`, signs it for
local use, copies it to `/Applications` and launches it.

A build like this can't update itself, because it isn't signed with the
release certificate, so its menu has no **Install Update** item. To update it,
run `git pull && make install`. To switch to the self-updating release,
install the DMG over the top. Your settings carry over.

## Make targets

| Command        | What it does |
|----------------|--------------|
| `make build`   | Compiles a release build with SwiftPM |
| `make test`    | Runs the full test suite (`swift test`) |
| `make run`     | Builds `build/Look Away.app` and launches it from there, for a quick dev loop |
| `make install` | Builds, copies the app to `/Applications` and launches it |
| `make bundle`  | Builds `build/Look Away.app` without launching it |
| `make dist`    | Packages a release into `dist/` (see [releasing](docs/releasing.md)) |
| `make verses`  | Regenerates the built-in verse list from the BSB |
| `make artwork` | Re-renders the app icon and DMG background from their SVGs |
| `make clean`   | Removes build output |

## Tunables

The durations aren't settings in the app. Change them in code and rebuild:

| Value | Default | Where |
|---|---|---|
| Time between breaks, countdown length, delay length | 20 min, 20 s, 5 min | `Sources/LookAwayCore/Config.swift` |
| Meeting detection delay (default) and grace period | 15 s, 30 s | `Sources/LookAwayCore/MeetingSettings.swift` |
| Chosen-app settle time and grace period | 5 s, 20 s | `Sources/LookAwayCore/AppPauseSettings.swift` |
| Verse reading time, Done hold with a verse, soft length limit | 5 s, 4 s, 280 characters | `Sources/LookAwayCore/VerseSettings.swift` |
| Done hold without a verse | 1.2 s | `Sources/LookAway/AppModel.swift` |
| Minimum time between update checks | 15 min | `Sources/LookAway/Updater.swift` |

The **Delay 5 min** button label is written out in
`Sources/LookAway/BreakView.swift`, so update it if you change the delay.

## Project layout

- `Sources/LookAwayCore` has no UI and depends only on Foundation, so all of
  it can be tested.
  - `Config` holds the durations. `Timekeeper` abstracts the clock.
  - `BreakScheduler` is the state machine that drives breaks.
  - `Schedule` and `ScheduleStore` define the schedule and store it.
  - `MeetingSettings`, `AppPauseSettings` and `VerseSettings` are the other
    settings models. `ChosenApp` is an app picked for either list.
  - `MeetingMonitor` (in `MeetingDetector.swift`) and `FocusedAppMonitor` are
    the two detectors, built on a shared `DebouncedMonitor`. Both report to the
    same hold on the scheduler, which keeps the popup back until the last one
    lifts.
  - `DailyVerses` is the built-in verse list. `DailyVerses+All.swift` is
    generated, so don't edit it by hand.
  - `UpdateChecker` asks GitHub Releases whether a newer version is out.
- `Sources/LookAway` is the AppKit and SwiftUI app.
  - `AppDelegate` starts the app. `AppModel` connects the scheduler to the UI.
  - `StatusMenuController` is the menu bar item and its menu. `LogoEye` draws
    the resting icon.
  - `BreakPanel` and `BreakView` are the floating popup. `Sound` plays the
    chime.
  - `SettingsWindowController`, `SettingsView`, `MeetingSettingsView`,
    `AppPauseSettingsView` and `VerseSettingsView` make up the settings
    window. `AppPicker` is the chips-and-search control.
  - Probes that read from the system:
    - `SystemActivityProbe`: microphone and camera use, through CoreAudio and
      CoreMediaIO
    - `FrontmostAppProbe`: the app in front
    - `InstalledApps`: the scan of installed apps
    - `SystemEvents`: sleep, wake, screen lock and clock changes
  - `LaunchAtLogin` handles the login item. `Updater` downloads a release,
    verifies its signature and swaps it in.
- `Tests/LookAwayCoreTests` tests the scheduler, the schedule, meeting and app
  detection, verses and update checks. The tests run against a fake clock, a
  fake device probe, a fake frontmost-app probe and a fake GitHub.
- `Resources` holds `Info.plist`, the app icon and the DMG background.
  `Resources/Artwork` has their SVG sources.
- `scripts` holds:
  - the verse list and its generator
  - the release packaging script and its DMG layout
  - the artwork renderer
  - the Homebrew cask template
- `.github/workflows/release.yml` builds, notarizes and publishes a release
  when a `v*` tag is pushed. See [docs/releasing.md](docs/releasing.md).

## The built-in verses

`scripts/daily-verse-references.txt` lists the verse of the day references,
one per line, in the order the days use them. `make verses` regenerates
`Sources/LookAwayCore/DailyVerses+All.swift` from the official BSB text, so no
verse is typed by hand.

While generating, it:
- closes a quotation mark that the verse boundary leaves open
- drops a stray closing quotation mark
- leaves out "Selah"

It rejects the whole list if a reference is unknown or repeated, or if a verse
is longer than 280 characters.

## Artwork

The app icon and DMG background are drawn as SVGs in `Resources/Artwork`.
`make artwork` renders them to `Resources/AppIcon.icns` and
`Resources/dmg-background*.png`, which are committed. It needs `rsvg-convert`:

```bash
brew install librsvg
```

## Releasing

See [docs/releasing.md](docs/releasing.md).
