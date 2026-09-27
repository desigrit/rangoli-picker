# <img src="docs/images/rangoli-icon.png" alt="" width="32" height="32" align="absmiddle"> Rangoli

**Pick a color anywhere on your Mac.** Rangoli lives in the menu bar and copies the color under your cursor in one click.

I loved the beautiful, effortless feel of the Windows color picker and wanted that same little moment on macOS. Rangoli is my take: a tiny eyedropper, a live color preview, and a shortcut that gets out of your way as soon as you have the color you need.

![Illustrative desktop mockup of Rangoli sampling blue beside a polar bear peeping through Arctic ice](docs/images/peeping-polar-bear-mockup.png)

*An illustrative desktop mockup inspired by “Icy Window” by Audun Rikardsen.*

## A closer look

| Pick your format | See the color before you copy |
|:---:|:---:|
| ![Rangoli's compact format selector, showing HEX and a close button](docs/images/format-bar.png) | ![Rangoli's live preview, showing a swatch, hex code, and nearest color name](docs/images/color-preview.png)

The Settings popover keeps the two things you may want to change close at hand: your shortcut and whether Rangoli starts at login.

## What it does

- Open Rangoli or press **Control–Option–C**. Move over any pixel; left click to copy its code and close.
- Switch between Hex, RGB, HSL, HSV, CMYK, and Lab from the small bar at the top of the primary display. Rangoli remembers your last choice.
- See a swatch, the current code, and the nearest name from the [CSS named-color list](https://www.w3.org/TR/css-color-4/#named-colors) next to your cursor.
- Right click, press Esc, click X, or press the shortcut again.

## Build and run

Rangoli requires **macOS 14 or later**. It is written in Swift and AppKit, has no third-party dependencies, and builds with Swift Package Manager and the Apple Command Line Tools. A prebuilt download is not available yet.

```sh
git clone https://github.com/desigrit/rangoli-picker.git
cd rangoli-picker
zsh Scripts/build-app.sh
open dist/Rangoli.app
```

On the first pick, allow **Screen & System Audio Recording** in macOS System Settings. Rangoli uses ScreenCaptureKit to sample the visible pixel under the cursor while the picker is open. It excludes its own interface from capture, and stops capture and pointer polling when you dismiss it. If macOS still blocks picking after you grant access, quit and reopen Rangoli, then choose **Pick** from the menu bar.

If you plan to keep the app in `/Applications`, move it there **before** granting screen access or enabling Launch at Login. Rebuilding with the default ad hoc signature may require you to refresh the macOS permission. You can supply a stable signing identity with `RANG_CODESIGN_IDENTITY` when building.

## A few details

- Rangoli samples at native display resolution and converts the result to sRGB before formatting it.
- Color names are the nearest of the 148 opaque CSS named colors. They are descriptive approximations, not exact matches for every screen color.
- CMYK is an approximation of an sRGB screen color; it is not a print profile conversion. Lab uses a D50 white point.
- The pixelated **Radiant Star** icon has a matching monochrome menu bar version.

## Checking the build

`Scripts/build-app.sh` runs the color and coordinate checks before packaging `dist/Rangoli.app`. After granting screen access, you can run the live sampling check:

```sh
dist/Rangoli.app/Contents/MacOS/Rangoli --check-sampling .build/sampling-check.json
```

That check samples foreground colors and a single Retina pixel, verifies that Rangoli's own panels are excluded, and exercises cursor restoration. The full implementation is in [`Sources/`](Sources/); the icon generator is [`Scripts/generate-icon.swift`](Scripts/generate-icon.swift).
