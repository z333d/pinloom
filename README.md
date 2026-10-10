<p align="center"><img src="docs/images/icon.png" width="96" height="96" alt="Pinloom icon"></p>

# Pinloom

Keep images, videos, webpages and notes in view while you work. Pinloom is a native macOS menu bar
app with a hanging line that floats above your apps, including full-screen Spaces.

[简体中文](docs/i18n/README.zh-Hans.md) · [Español](docs/i18n/README.es.md)

![Pinloom's line with import controls and an editable note](docs/images/preview.png)

## Use it

Opening Pinloom from Applications shows the line, even if it is already running
and hidden. Launching automatically at login keeps it hidden until you open it.

Click the pin icon in the menu bar to show or hide the line. Right-click it to
open the menu. The line stays open until you hide it; moving the pointer into
the menu bar does not open it.

- **Paste** adds a clipboard image, copied video file, or webpage address.
- **Add files…** opens a picker for images and local videos. You can also drop files or links on the line or menu bar icon.
- **Add webpage…** opens an address field. Web cards support scrolling, text selection, links, back/forward, reload and opening in your browser.
- Videos start paused and muted, with native playback and seek controls. Import creates a private copy so moving the original does not break the card. Playback position is saved; hiding the line pauses playback.
- **New note** adds editable text and checkable to-dos. Content is saved locally.
- Press **Return** in a to-do to insert the next one below it; text after the
  cursor moves to the new item. Return on an empty item removes it and ends
  editing. **Escape** ends editing without removing the item.
- Drag a card's **clip** to move that card; it swings as you move it.
- Drag the **bottom-right corner** to resize a card. Position and size are remembered.
- Select note text and press **Command+C**, or use **Copy note** to copy the whole note, including tasks.
- Click an image to copy it, double-click for a zoomable preview, or hold to open Markup.
- Pin an image into its own movable reference window. References own snapshots and remain available if the source moves.
- **Hide line** hides the board without deleting anything. Removing a card keeps the original file; **Move to Trash** explicitly deletes it.

The menu shows recovery and reference controls only when relevant. **Arrange**
contains reset positions and take images down; **Options** contains sounds and
open at login. Manually added images stay until you remove them; scroll
horizontally when they do not fit.

Pinloom does not watch screenshot folders, change capture settings, or register
global hotkeys. Keep using your preferred screenshot tool and add the images
you need. Standard text editing commands work inside notes.

Webpages load only after you show the line. They use Pinloom's own WebKit session,
not your browser's signed-in session. Some sign-in flows, popups and downloads
work best in your browser; use the card's open button. Local video format and
codec support follows AVFoundation (including supported MP4, MOV and M4V files).

## Size and compatibility

macOS 14 or later, Apple silicon and Intel. Interface languages: English,
Spanish and Simplified Chinese. Swift, AppKit, SwiftUI, AVKit and WebKit. Images,
videos and notes stay local. Web cards connect to the sites you add; Pinloom
does not require an account or send analytics.

New images preserve their aspect ratio and fit a 306 × 234 point image area,
plus the frame. Notes start at 320 × 280 points, with a 240 × 220 minimum.
Both can grow to the current display's usable space (85% of its width minus
40 points, and its height minus 100 points), instead of fixed zoom caps.
Previously saved sizes are retained; smaller displays temporarily fit the
cards without overwriting those preferences. Video cards start at 384 × 260
and webpages at 480 × 360, with the same display bounds. Notes use one scrolling area
for text and tasks.

## Build and install

```sh
git clone https://github.com/z333d/pinloom.git
cd pinloom
swift test
swift scripts/check-strings.swift
SIGN_IDENTITY=- scripts/build-app.sh release
open build/Pinloom.app
```

The build script creates a universal `build/Pinloom.app`. Drag it to Applications
for everyday use. `scripts/make-dmg.sh` creates an installation disk image without
opening Finder or changing window-manager settings. CI also produces an app ZIP
under [Actions](https://github.com/z333d/pinloom/actions).

Local and CI builds default to ad hoc signing, **not Apple-notarized**. The build
never automatically selects a Developer ID from the keychain. Distribution with
a Developer ID requires an explicitly supplied `SIGN_IDENTITY`; disk image notarization additionally
requires your own `NOTARY_PROFILE`. This repository does not include signing credentials.

## Moving from earlier local builds

Pinloom uses its own bundle ID (`io.github.z333d.pinloom`) and Application Support
directory. On first launch it copies saved images, notes, card layout and
reference snapshots from earlier local builds under `app.tendedero.Tendedero`.
Original data stays in place. Existing Pinloom data is not overwritten; a failed
file copy is retried on the next launch.

If the old screenshot inbox mode is still applied, its saved capture settings
are restored once. Pinloom never enables that mode. Quit the earlier app before
opening Pinloom.

## Development notes

`Sources/Pinloom` contains the app; `Tests/PinloomTests` covers native controls,
clipboard behavior, persistence, layout, references and upgrade migration.
Run `swift scripts/check-strings.swift` after changing interface text.

The background resize cursor uses an optional private WindowServer property.
Visible resize handles remain available if that property is unsupported. See
[the implementation notes](docs/background-cursor.md) and the manual checks there.

To regenerate the documentation images without opening the app:

```sh
swift scripts/make-icon.swift docs/images/icon.png
PINLOOM_NOTE_PREVIEW="$PWD/build/note-preview.png" swift test --filter testNoteEditorRoutesTextAndCheckboxChangesAndNativeHitTargets
swift scripts/make-readme-art.swift build/note-preview.png docs/images/preview.png
```

## Origin and license

Pinloom is independently maintained by [z333d](https://github.com/z333d), based on
the MIT-licensed code of [Tendedero](https://github.com/alejandrobujan/tendedero) by
Alejandro Buján. The original copyright and license are preserved in [LICENSE](LICENSE)
and [NOTICE](NOTICE). Pinloom uses a new name, icon and documentation artwork and
is not an official release of, or endorsed by, the upstream project.
