# LumeToggle

A menu bar app for Lume Cube Panel Pro lights. Click to switch your panels on and off, or let them turn on by themselves whenever your camera is in use.

## Requirements

- A Mac with Apple silicon, running macOS 13 Ventura or later
- Lume Cube Panel Pro lights that you have already set up in the Lume Cube mobile app

## Install

1. Open `LumeToggle.dmg` and drag **LumeToggle** to **Applications**.
2. Open LumeToggle from Applications. It runs in the menu bar and has no Dock icon.
3. When macOS asks for Bluetooth access, click **Allow**.

## Before you connect: quit the mobile app

Each panel accepts only one Bluetooth connection at a time. If the Lume Cube app on your phone is open, it can keep the panels to itself and LumeToggle can't reach them.

**Fully close the Lume Cube app on your phone** (swipe it away, don't just switch apps), then click **Reconnect** in LumeToggle. You can also turn off Bluetooth on the phone.

## Using it

- **Left-click** the menu bar icon to switch all panels on or off.
- **Right-click** (or Option-click) to open the controls:
  - **Brightness** and **temperature** sliders at the top set every panel at once. They replace any per-panel settings.
  - Click a panel's name to expand it. There you can switch that panel on or off, set its own brightness and temperature, and give it a name. The name is only used in LumeToggle.
  - **Turn On With Camera** switches the panels on when any app starts using a camera, and off a few seconds after it stops.
  - **Launch at Login** starts LumeToggle when you log in.

The menu bar icon shows a filled panel when the lights are on, an outline when they're off, and a slashed panel when no panels are connected.

## Troubleshooting

- **The icon stays slashed.** Check that the panels are powered on and nearby, and that the Lume Cube phone app is closed. Then right-click and choose **Reconnect**.
- **No panels ever connect.** Open **System Settings → Privacy & Security → Bluetooth** and make sure LumeToggle is switched on.
- **The sliders don't match the panels.** LumeToggle can't read settings back from the panels. If you changed them from the phone app, move a slider to send LumeToggle's settings again.
