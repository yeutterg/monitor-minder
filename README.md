# Monitor Minder

A small macOS menu bar app that remembers how your displays are arranged and snaps them back.

- **Named layouts for each set of displays.** Save the current arrangement as "Desk", "Presenting" and so on. Only layouts for the displays that are connected are shown.
- **Arrangement, or arrangement + windows.** A layout records each display's position, resolution and refresh rate. It can optionally record where every window is, and move the windows back. Nothing is tiled.
- **Drift check.** If a display moves a few points (the pointer stops crossing) or comes back at the wrong resolution, the menu says what changed and offers **Snap Back**.
- **Auto-restore** when a set of displays connects or wakes. Changes made on purpose in System Settings are left alone and just show as drift.
- **Shortcuts:** ⌃⌥1 to ⌃⌥9 apply the layouts in order.
- **Display names:** click a display in the diagram to rename it.

Requires macOS 26 or later.

## Build and run

```sh
swift test                  # core tests
scripts/install.sh          # build, install to /Applications and launch
.build/debug/MonitorMinder --dump                                  # print connected displays as JSON
.build/debug/MonitorMinder --preview --page main|save|settings     # popover in a window
```

## Where settings live

Everything is in one JSON file:

```
~/Library/Application Support/MonitorMinder/config.json
```

It's outside the app bundle on purpose. Writing into a signed app breaks its signature, `/Applications` isn't always writable, and updating the app would wipe it. **Settings › Config** has Show in Finder, Export and Import. To remove everything, delete the app and that folder. Set `MONITOR_MINDER_CONFIG=/path/to/config.json` to use a different file, for example while developing.

## Permissions

Arrangements need no permission. Saving or moving windows needs **Accessibility** access (Privacy & Security › Accessibility). The app asks for it the first time you save a layout with windows.

## Limits

- Windows are only seen on the current Space. Full-screen and minimized windows are skipped.
- Windows are matched by app, then by title, then by order. A browser with changing tab titles can swap windows within the same app.
- Displays are identified by vendor, model and serial number. Two identical monitors that report no serial number are told apart by port order, so swapping their cables swaps them.
- Rotation isn't saved. macOS has no public API for setting it.
