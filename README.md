# vibecodeMaxing

A native macOS notch companion for long-running AI work. Start a timed session,
close your MacBook, and let your local agents continue working.

Built for Apple silicon MacBooks, including the M4 MacBook Air. Requires macOS 14+
and Swift 6+ to build. No third-party packages or full Xcode installation required.

## Build and open

```sh
zsh scripts/build.sh
open dist/vibecodeMaxing.app
```

The build includes the app icon in all standard macOS sizes and a vector menu-bar
mark. Both are generated from the native vector artwork in
`scripts/generate-icon.swift`; `dist/logo.png` provides a logo preview.

The panel starts collapsed, flush with the top edge. Its height matches the
built-in display's notch, with just 12 points added on either side. Click it to
open the compact controls; click again, press Escape, or click outside the panel
to collapse. The duration menu stays interactive while open. Collapsing the panel
does not end a running session. Hovering does not open or resize it. Only the star
is visible on the left while collapsed. Battery status appears to the right of
the notch, with a percentage, only when expanded. The moon in
the menu bar also opens the panel and provides Quit. Displays without a notch
get a top-center panel. Resizing keeps the top edge fixed and respects Reduce Motion.
The expanded controls use the transparent `.clear` Liquid Glass variant on
macOS 26+, with an ultra-thin material fallback on earlier versions. The panel's
active appearance is preserved when another app receives focus, so its material
and accent colors do not fade to inactive grey. The surface extends above the physical
screen edge so its upper glass highlight is hidden rather than forming a rim
between the panel and the top edge.

Choose 30 minutes to 8 hours and click **Keep my agents running**. Approve the
native macOS administrator dialog, then wait for the active status before closing
the lid. Each session asks for authorization; no permanent privileged service or
password exemption is installed. Cancel the authorization dialog to abandon a
pending request.

## What a session does

- Applies `pmset -a disablesleep 1` for both battery and adapter power, and verifies
  the kernel's `SleepDisabled` state before showing an active session.
- Holds an IOKit idle-sleep assertion without keeping the display awake.
- Keeps the whole Mac awake, covering Codex, Claude Code, Cursor, and other local
  workloads without agent-specific integrations or reading prompts or transcripts.
- Requests screen locking when the lid closes. If locking cannot be confirmed
  within three seconds, the session ends.
- Restores normal sleep on End session, Quit, timeout, battery at or below 20%, or
  macOS serious/critical thermal pressure. Use on a hard, ventilated surface.

This prevents sleep; it does not resume failed agents, answer permission prompts,
or guarantee network connectivity. No token tracking or Telegram integration.

## Session guard

The bundled `vibecodeMaxingGuard` runs with administrator authorization for the session.
It runs only the fixed `pmset` sleep-override commands. It holds an exclusive lock,
validates the app's user and process start time, and watches an open lease file
with private permissions. The app refreshes that lease each second.

The guard restores sleep independently if the app crashes, the lease is deleted,
or its heartbeat is more than 20 seconds old. It also enforces the deadline,
battery cutoff, and thermal protection independently of the UI. Catchable
termination signals trigger cleanup. It refuses to start if another tool already
has the sleep override enabled. Avoid running competing sleep tools concurrently.

`disablesleep` is an undocumented macOS switch, and automatic locking uses the
private `SACLockScreenImmediate` symbol from Apple's login framework. These need
physical closed-lid validation on each supported macOS/hardware combination. An
unavailable lock symbol prevents session startup. This development build is
ad-hoc signed; public distribution requires Developer ID signing and notarization.

If the **guard itself** is forcibly killed, or the machine loses power during a
session, cleanup cannot execute. Restore sleep manually with:

```sh
sudo pmset -a disablesleep 0
```

The app never changes hibernation, display timers, standby, or network settings.

## Development and verification

```sh
zsh scripts/test.sh
zsh scripts/build.sh
dist/vibecodeMaxing.app/Contents/MacOS/vibecodeMaxing --snapshot "$PWD/dist/preview.png"
dist/vibecodeMaxing.app/Contents/MacOS/vibecodeMaxing --snapshot "$PWD/dist/collapsed.png" --collapsed
```

Tests cover watchdog expiry, app loss, battery and thermal boundaries, command
quoting, and read-only power telemetry. They do not change power settings or lock
the screen.

Bitmap snapshots use fallback materials because the WindowServer-composited
Liquid Glass effect cannot be captured with `NSView.cacheDisplay`. Inspect the
running app to verify the actual glass material.

### Physical closed-lid check

1. Disconnect external displays and power; charge above 20%.
2. In Terminal, run `while true; do date; sleep 5; done > /tmp/vibecodeMaxing-heartbeat.log`.
3. Start a session and approve the macOS dialog. Confirm `pmset -g` reports
   `SleepDisabled 1` and the UI reports an active session.
4. Close the lid for two minutes on a ventilated surface, then reopen it. Confirm
   the screen was locked and the heartbeat log has no sleep-sized gaps. Compare
   with `pmset -g log` for unexpected clamshell sleep.
5. End the session. Confirm `SleepDisabled` returns to 0 (or is absent from
   `pmset -g`) and normal lid sleep works again. Stop the Terminal loop with Ctrl-C.
6. Repeat while plugged in. In a separate session, force-quit **only the app** and
   verify the guard restores normal sleep within 20 seconds.

## Source layout

| Location | Purpose |
| --- | --- |
| `Sources/Afterglow` | SwiftUI panel, AppKit placement, menu, session controls, screen lock |
| `Sources/AfterglowCore` | Power telemetry, command escaping, watchdog policy |
| `Sources/AfterglowGuard` | Session-scoped administrator watchdog and restoration |
| `Tests/AfterglowCoreTests` | Read-only automated checks |
| `scripts/build.sh` | Release app bundle and ad-hoc signing |
