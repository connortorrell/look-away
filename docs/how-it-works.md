# How Look Away works

The [README](../README.md) covers the basics. This page is the full reference:
the rules the timer follows and the edge cases each setting handles.

- [The break timer](#the-break-timer)
- [The menu](#the-menu)
- [Schedule](#schedule)
- [Meetings](#meetings)
- [Chosen apps](#chosen-apps)
- [When holds overlap](#when-holds-overlap)
- [Verses](#verses)

## The break timer

- Every 20 minutes a popup opens on the display your cursor is on. It floats
  above your other windows and doesn't take keyboard focus, so whatever you're
  typing isn't interrupted.
- The 20-second countdown starts as soon as the popup appears. At zero it
  shows "Done", plays a soft chime and closes.
- **Delay 5 min** hides the popup and brings it back later with a fresh
  countdown. You can delay more than once.
- **Decline** closes the popup straight away.
- The next 20 minutes start when the popup closes, whether the break finished
  or was declined. A delay never restarts the 20 minutes.
- Sleep or screen lock pauses everything. Waking or unlocking starts a fresh
  20 minutes.

## The menu

Click the menu bar icon for:

- A live status line: "Next break in 12:34", or why reminders are held
- **Pause Reminders** / **Resume Reminders**
- **Take a Break Now**, which works at any time, even outside the schedule or
  during a meeting
- **Launch at Login**
- **Settings…**
- **Install Update**, which turns on and shows the version number when a
  new release is out
- **Quit Look Away**

Pausing from the menu outranks meeting and app detection.

The menu bar icon shows the current state:

| Icon | Meaning |
|---|---|
| The logo's eye | Counting down to the next break, or to a delayed one |
| Eye with a slash | A break is on screen |
| Pause circle | Paused from the menu |
| Moon | Outside your schedule |
| Video camera | Held for a meeting |
| Window | Held for one of your chosen apps |

## Schedule

Off by default, which means reminders run around the clock.

- Click the S M T W T F S circles to pick the days reminders run on.
- One start and end time covers every selected day. Set 9:00 AM to 5:00 PM
  once and the whole week follows it.
- **Different hours on some days** shows a row for each selected day, so any
  one of them can have its own hours. Those days get a dot under their circle.
  **Reset** puts a day back on the shared hours. Right-clicking a day circle
  offers both: give it custom hours, or put it back on the shared ones.
- An end time earlier than the start runs overnight, so 10:00 PM to 2:00 AM
  works for a night shift. The panel marks it "(next day)". The same start and
  end time means all day.
- Outside the schedule the menu bar shows a moon and the menu reads
  "Outside schedule — back Mon at 9:00 AM". The hold starts the moment the
  scheduled hours end.
- Edits are saved and applied immediately, without restarting the current
  20 minutes.

The settings window closes with ⌘W or Esc. If a text field has the keyboard,
the first Esc hands it back and the second closes the window. It reopens where
you left it.

## Meetings

Turn on **Pause reminders during meetings** to hold reminders while you're on
a call. Left off, nothing is watched at all.

### What counts as a meeting

- **Apps that count as a meeting** is a list of chips over a search field.
  Type to search every app installed on the Mac, click one to add it, and
  click the × on a chip to remove it.
- The first time the panel opens, the list is filled with the meeting apps you
  have installed: Zoom, Microsoft Teams, Slack, Pop, Discord, FaceTime, Webex,
  and the browsers Chrome, Edge, Arc, Brave, Firefox and Safari. If you clear
  the list, it stays clear.
- Detection watches **device use, not which app is in front**. Look Away asks
  macOS which processes are using the microphone. A Zoom window in the
  background during a call counts. Zoom just being open does not.
- Every meeting is tied to one of your chosen apps. Device use that can't be
  traced to one of them is ignored.
- Nothing is recorded, so Look Away never asks for microphone or camera
  permission.
- By default the microphone and the camera count. Audio output is a separate
  opt-in ([below](#listen-only-calls)).

### Camera

**Count camera use too** covers sitting muted on video.

- macOS reports camera use per device, not per app, so it can't say which app
  has the camera.
- So the camera counts only while one of your chosen apps is also playing
  audio: the call you're listening to. A chosen app just being
  open isn't enough, so Photo Booth using the camera while Zoom happens to be
  running doesn't count.
- Browsers never count for the camera, even while playing audio. A browser
  plays something most of the day, so any website using the camera would look
  like a meeting. Browsers still count for the microphone, where macOS names
  the process.

### Listen-only calls

**Count audio playing too**, under *Also detect listen-only calls*, is off by
default and best left that way.

- Audio coming *out* of an app is a weak signal. A YouTube video, a Slack ping
  and a call all look the same. With browsers and chat apps in the list, this
  will sometimes hold reminders while you're just browsing.
- Turn it on only if you join calls that release the microphone entirely. Most
  apps mute in software and keep the microphone open, so they're already
  detected.

### Timing

- **Detection delay** (15 seconds by default) is how long the microphone,
  camera or audio signal has to last before it counts. A notification chime or
  a quick "can you hear me?" doesn't hold anything.
- A **30-second grace period** keeps a meeting on after the signal stops, so
  a moment on mute, or the gap between back-to-back calls, doesn't let a popup
  through. It's also why a break owed at the end of a call arrives about half
  a minute after you hang up.
- Both apply only to changes seen while watching. Turning detection on,
  editing its settings or waking the Mac reads the current state directly. A
  call already under way holds at once, and one that ended during sleep is
  released at once.

### Breaks during a call

- **The 20 minutes keep running through a call.** Only the popup is held back.
  - A break that comes due during the call opens when you hang up, once the
    grace period has passed.
  - A call shorter than the time left changes nothing, so the break lands when
    it would have anyway, not 20 minutes after the call.
  - Either way it's one break, never a queue of them.
- A meeting that starts during a break closes the popup. You never got that
  break, so it's owed again when the call ends.
- During a meeting the menu bar shows a video camera, and the menu reads
  "Zoom meeting — next break in 4:32", or "break when you're free" once a break
  is due.
- That stays true even if you **Delay** a break you took by hand during the
  call. The delay's deadline becomes the one the meeting owes.
- The last line of the settings panel shows what detection sees right now:
  "Not in a meeting right now" with the apps that count, or "Zoom is on a call.
  Reminders are held until it ends." Use it to check that a call is picked up,
  and by which app.

### Meetings and the schedule

The schedule wins. If the scheduled hours end during a call, the hold hands
over to the schedule and nothing is owed when the call ends. The same goes for
a break you took by hand outside the hours and then delayed during a call: the
schedule's hold takes over when the call ends.

### Capture processes

An app doesn't always use the microphone under its own bundle ID, so each app
in the list carries the ID patterns that belong to it:

- Zoom captures from `us.zoom.caphost` alongside `us.zoom.xos`.
- Electron apps capture from a nested helper process.
- FaceTime, and an iPhone call answered on the Mac, capture from the system's
  call daemon, `com.apple.avconferenced`.
- Chromium browsers are matched through their helper process.
- Safari hands capture to a shared WebKit process that doesn't say which
  browser it came from, so the Safari entry covers any WebKit browser.

## Chosen apps

A full-screen game uses no microphone or camera, so meeting detection can't
see it. Turn on **Pause reminders in certain apps** to hold reminders while a
particular app is in front. Left off, nothing is watched.

- **Apps that pause reminders** uses the same chips-and-search control as the
  meeting list. It starts empty, because which apps shouldn't be interrupted
  is personal.
- **Only the app in front counts.** An app just being open does nothing, so a
  game left running in the background all week doesn't switch reminders off
  all week. No permissions are needed.
- Switching to the app has to settle for 5 seconds before it counts, so
  clicking through a window to reach something behind it holds nothing.
- Leaving the app has a 20-second grace period, so switching out to look
  something up and straight back doesn't land a popup on your return.
- Editing the list takes effect at once. Removing the app you're in releases
  the hold immediately, without waiting out the grace period.
- Look Away's own windows don't count as leaving, so opening Settings mid-game
  keeps the hold.
- At launch, the app already in front counts straight away.
- **The 20 minutes keep running**, just as during a meeting. A break that comes
  due opens when you leave the app. A session shorter than the time left just
  carries on counting. It's one break either way.
- During a hold the menu bar shows a window icon, and the menu reads
  "In Minecraft — next break in 4:32", or "break when you're done" once a
  break is due.

## When holds overlap

A meeting and a chosen app can hold reminders at the same time, for example a
call with a game still up. The popup waits until both have ended. The menu
names the meeting while there is one, since that's the hold whose end someone
else decides.

## Verses

Turn on **Show a verse during breaks** to show a verse under the countdown.
Left off, the popup is unchanged.

- **Read, then look away.** Reading keeps your eyes on the screen, which is
  the opposite of the point. So the break opens with 5 seconds to read, under
  "Read, then look away and meditate", before the countdown starts. That time
  is added to the break, so all 20 seconds of the countdown are still spent
  looking away.
- The verse dims during the countdown, so it's still there if you glance back.
  It returns in full at Done, and the popup stays up for 4 seconds instead of
  about 1.
- **Verse of the day** is built in: 430 short verses from the Berean Standard
  Bible, one per day, the same one at every break that day. It needs no
  network. The BSB is in the public domain.
- **My verses** is your own list, in any translation. Paste the text and
  optionally add a reference.
  - Breaks step through the list in order, one verse per break, and keep their
    place across restarts.
  - Only a finished break moves on. A delayed or declined break brings the same
    verse back.
  - Drag to reorder, or use each row's menu.
  - Past 280 characters the count turns orange, because a long verse is hard to
    take in at a glance. It's still saved and shown.
  - An empty list falls back to the verse of the day.
