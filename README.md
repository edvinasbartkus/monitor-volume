# Monitor Volume

A tiny, MIT-licensed macOS menu-bar app that makes keyboard volume keys control
**the monitor selected as the default audio output**. No brightness controls,
virtual audio drivers, analytics, network access, or Lunar dependency.

## Requirements

- Apple Silicon Mac, macOS 13 or later.
- A monitor supporting DDC/CI speaker volume (VCP `0x62`). Enable DDC/CI in the monitor's menu.
- A connection that passes DDC through (usually direct USB-C/DisplayPort; HDMI support varies).
- The monitor's audio device must have HDMI or DisplayPort transport in CoreAudio.
  USB audio devices and virtual/aggregate devices are deliberately not routed in this first version.
- Accessibility permission for the media-key interceptor. Some macOS versions also require Input Monitoring.

Tested so far: the app builds, unit tests pass, and read-only diagnostics successfully
match and read volume from an M2 + LG HDR 4K over DisplayPort. End-to-end keyboard
and hardware-write behavior still requires permission-granted testing on the Mac.

## Build and run

Install Xcode or Apple's Command Line Tools, then:

```sh
./scripts/build.sh
```

This creates an ad-hoc-signed `dist/MonitorVolume.app`. For a stable permission
identity, move it to its final location **before granting permissions**:

```sh
ditto dist/MonitorVolume.app /Applications/MonitorVolume.app
open /Applications/MonitorVolume.app
```

1. Quit Lunar, MonitorControl, or other apps listening for volume keys; competing
   interceptors can consume or double-handle the same key.
2. Choose your monitor in **System Settings → Sound → Output**.
3. Click the menu-bar speaker icon, then **Enable keyboard control…**. Enable
   Monitor Volume in **Privacy & Security → Accessibility**. If the keyboard tap
   is still unavailable, also enable it in **Input Monitoring**, then quit/reopen the app.
4. Press volume up/down/mute. Switching output to Mac speakers, headphones, or
   Bluetooth leaves normal keyboard behavior untouched.

The menu also has volume up/down/mute buttons (work without keyboard permissions),
Pause, and Refresh. There is no automatic launch-at-login setup; add the app in
**System Settings → General → Login Items** if wanted.

## Behavior

- A case-insensitive exact name match must be unique among both discovered monitors
  and all connected HDMI/DisplayPort audio outputs, including ones without DDC.
  It never targets the display under the cursor or simply the only connected monitor.
- If names differ or identical models are connected, use **Link current output to
  monitor**. The explicit link is stored locally per audio-device UID. Moving to a
  different physical port can invalidate it; link again instead of guessing.
- Choose **Volume step** in the menu: **1%, 2%, 3%, 5%, or 6% per tick**. The default
  is 1%, and your selection is saved across app restarts. The setting affects
  keyboard keys and menu buttons. Hold **Shift + Option** with a volume key to
  override a larger step with 1%. Steps are rounded to the monitor's integer
  hardware range, with a minimum of one register unit.
- Mute sets monitor volume to zero. Unmute restores the last nonzero value in the
  current session, including across Refresh, sleep/wake, and output changes. If the
  app starts at zero without a remembered level, the initial unmute fallback is 25%.
- Rapid key presses are coalesced. DDC runs on a serial background queue, not
  inside the event tap. Writes are followed by reads to confirm the requested value.
- Unmatched output, unsupported DDC, paused state, or failed writes disable
  interception. On failure, subsequent keys pass through; the already intercepted
  key cannot be replayed. Use Refresh after fixing the connection.
- The app does not show a volume popup. Only the monitor's own volume overlay
  appears, if its firmware displays one. The current level is still shown in the
  menu bar item's menu. The macOS system volume slider remains disabled for
  hardware-only display audio.
- Output changes, screen changes, and sleep/wake invalidate pending work. The
  default output is rechecked at each key press and immediately before each write.
  A hardware write already in progress cannot be cancelled if the output changes
  at precisely that instant.
- The monitor's physical volume changes are polled while idle every few seconds.

## Diagnostics (no volume changes)

```sh
/Applications/MonitorVolume.app/Contents/MacOS/MonitorVolume --diagnose
# Or, before installing:
swift run MonitorVolume --diagnose
```

Prints the default audio output, permission status, discovered monitors, current
DDC volume/range, and matched monitor. An unbundled CLI's permission status may
not match the installed app's status.

If DDC reads fail, quit other monitor controllers, enable DDC/CI, try connecting
without a dock/adapter, and choose Refresh. DisplayLink generally does not pass DDC.

## Development

```sh
swift build
swift test
./scripts/build.sh
```

Tests use XCTest, requiring full Xcode. If `xcode-select` points at Command Line
Tools and XCTest cannot be found, use your installed Xcode path for that command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

The build script also supports `SIGNING_IDENTITY="Developer ID Application: …"`.
Ad-hoc-signed local builds are not notarized. Distribution to other Macs requires
appropriate signing/notarization or users handling Gatekeeper themselves. macOS
may require re-granting permissions after a locally signed rebuild.

### Structure

- `Sources/VolumeCore/`: testable volume math, media-key decoding, safe route matching.
- `Sources/MonitorVolume/`: CoreAudio output detection, serialized DDC, event tap,
  and menu-bar app.
- `Tests/VolumeCoreTests/`: volume/mute/range, routing, and media-key tests.
- `Vendor/`: [AppleSiliconDDC](https://github.com/waydabber/AppleSiliconDDC) by
  @waydabber, MIT-licensed, pinned and vendored with small correctness fixes.

### Manual acceptance checklist

With other monitor controllers quit:

- [ ] Default monitor output: up/down/mute change the monitor's actual volume.
- [ ] Unmute restores volume; held mute does not oscillate.
- [ ] Hold volume up/down: responsive, clamped, no late queued changes.
- [ ] Mac speakers/headphones selected: native volume keys work; monitor unchanged.
- [ ] Switch output while holding a key: no stale writes to the previous route.
- [ ] Unplug/reconnect, sleep/wake, and Refresh safely re-establish the route.
- [ ] Pause and Quit restore normal keyboard behavior.
- [ ] Permission denied/revoked: no interception; menu buttons still work.
- [ ] DDC disabled: clear unavailable state, keys passed through.
- [ ] Multiple identical monitors: no automatic ambiguous match; explicit link works.

## License

MIT. Third-party MIT attribution is preserved in `Vendor/AppleSiliconDDC-LICENSE`
and bundled in the built app. This is an independent project inspired by Lunar's
volume-key behavior; no Lunar source code, branding, or assets are used.

DDC uses private macOS IOAVService/CoreDisplay APIs, which may break with OS
updates. No sandbox entitlements or kernel extension are required. Not intended
for the Mac App Store.
