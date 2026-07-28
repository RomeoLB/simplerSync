# simplerSync

`rlb-sync-screens.brs` is a BrightSign zone plugin (`SyncScreenPlayback`) that drives
synchronized multiscreen video-wall playback across BrightSign players, using
`roSyncManager` + PTP for frame-accurate sync and a `sync-config.json` file to assign
each physical player to a wall/screen position instead of hardcoding per-device settings
into the presentation.

## Prerequisites

- **Enhanced Sync must be disabled** in the BrightAuthor:connected presentation — this
  plugin replaces BAC:on's built-in sync mechanism entirely.
- All players in a wall must be networked with PTP reachable between them (same
  `ptp_domain`, matching `ptp_interface`).
  - **Wi-Fi is not supported as the PTP interface** — the plugin intentionally skips
    writing `ptp_interface` to the registry when it's Wi-Fi, due to a known BrightSign
    OS bug (OS-20946) where Wi-Fi sync doesn't work correctly. Use a wired interface.
- A `sync-config.json` asset must be included in the presentation's asset pool, named to
  match the presentation itself: `<presentationName>.json`. At startup the plugin copies
  this file to `sync-config.json` on the player's default drive and reads it from there.

<!-- TODO(rlb): fill in the exact BrightAuthor:connected steps for registering this
     script as a zone plugin (plugin name, which zone(s) it's attached to, how the
     matching <presentationName>.json asset gets added to the asset pool) — this needs
     to come from your own BAC:on workflow rather than being inferred from the script. -->

## `sync-config.json` format

The file is a **JSON array of wall configs** — one entry per physical video wall (i.e.
one entry per group of players that sync together), not one entry per player. On
startup, every player reads the *entire* array and searches every entry's `screens` map
for its own serial number to figure out which wall it belongs to.

```json
[
  {
    "config_file": "Frozen 2x2.json",
    "Multiscreen_Mode_Enabled": false,
    "ptp_domain": "0",
    "ptp_interface": "eth0",
    "master_serial": "26G393001646",
    "wall": {
      "columns": 2,
      "rows": 2,
      "screen_width_mm": 0,
      "screen_height_mm": 0,
      "bezel_mode": "identical"
    },
    "screens": {
      "screen1": {
        "serial": "26G393001646",
        "MultiscreenWidth": 2,
        "MultiscreenHeight": 2,
        "MultiscreenX": 0,
        "MultiscreenY": 0,
        "x_pct": 0,
        "y_pct": 0,
        "bezel_inputs": { "no_compensation": true }
      },
      "screen2": { "...": "..." }
    }
  }
]
```

Field notes:

| Field | Meaning |
|---|---|
| `master_serial` | Serial number of the sync **leader** for this wall. Any player whose own serial matches this becomes the leader (`roSyncManager.SetAsLeader(true)`); every other player in the same entry is a follower. |
| `ptp_domain` / `ptp_interface` | Written to the player's registry if different from what's currently stored; a mismatch triggers a reboot so the new PTP config takes effect. |
| `screens.<name>.serial` | Serial number of the player that should play the zone/state named `<name>`. This is how a player figures out which zone content it's responsible for (`m.bsp.sign.zoneshsm[0].statetable[<name>]`) — the zone/state name in the presentation must match this key. |
| `Multiscreen_Mode_Enabled` | When `true`, the player applies `MultiscreenWidth/Height/X/Y` and `x_pct`/`y_pct` bezel compensation from its `screens` entry to the video player. |

If a player's serial isn't found in any entry's `screens` map, it logs
`No matching wall config found in sync-config.json for serial ...` and does not get a
wall/screen/role assigned.

## Master/slave (leader/follower) behavior

- Role is decided purely by comparing the player's own serial number
  (`roDeviceInfo.GetDeviceUniqueId()`) against `master_serial` for its matched wall entry.
- The leader drives playback (`PlayfilesFromStorageMedia`); followers play in response to
  `roSyncManagerEvent`s from the leader.
- A sync watchdog reinitializes `roSyncManager` if no sync event arrives within ~90
  seconds (about 3x an expected clip duration), on both leader and followers. After 2
  failed reinit attempts it reboots the player instead.

## Live group/schedule changes (BSN.cloud)

The plugin subscribes to `roControlCloud` and listens for the same
`checkforcontent`/`updateSettings`/`updateSchedule` messages BrightSign's own supervisor
uses. If BSN.cloud pushes `updateSettings: true` or `updateSchedule: true` — e.g. after
moving the device to a different BSN.cloud group, or changing its schedule — the plugin
**reboots the player**. This is intentional: rebooting is the only way for the plugin to
force a full re-read of `sync-config.json` and a fresh sync-spec/schedule pull from
BSN.cloud, since a plain presentation restart (`bsp.Restart("")`) only reloads content
already synced locally and doesn't talk to BSN.cloud at all.

Anyone deploying this should expect: **any settings or schedule change pushed from
BSN.cloud causes an unannounced reboot**, not just a soft content refresh.

## Playlist / seamless looping behavior

The plugin rebuilds its playlist from either a populated media-library zone or a live
data feed on the matched screen's zone. A single-item playlist automatically plays in
seamless loop mode (no gap between repeats); as soon as a second item is added (e.g. a
live data feed grows), the plugin disables seamless mode and restarts the video player so
end-of-file events fire correctly between items — this recalculation happens every time
the playlist is rebuilt, so it stays correct as the feed grows or shrinks.

## Diagnostics

- PTP state transitions and periodic polling (`roPtp`) are logged to the console and via
  `roSystemLog`.
- A one-time sync-timing trace (`SyncTimingLog: ...` lines) runs for the first 3 playback
  loops after boot, showing role, loop number, sync ID, sync-event-received time, and
  video-playing time — console output only, no file is written to storage.

## Known limitations

- Wi-Fi cannot be used as the PTP sync interface (see Prerequisites).
- Any BSN.cloud settings/schedule push reboots the player rather than doing a lighter
  content-only refresh.
- `sync-config.json` must be regenerated/re-uploaded as part of the presentation asset
  pool any time wall membership, screen assignment, or PTP config changes — the plugin
  only reads it at startup (or after the reboot triggered by a settings/schedule push).

## Files in this repo

- `rlb-sync-screens.brs` — the plugin.
- `sync-config.json` is **not** included here — it's presentation/deployment-specific
  (one file per set of video walls) and must be authored and added to each presentation's
  asset pool separately, named `<presentationName>.json`. See the format above.
