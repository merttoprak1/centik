# Centik

Centik is a menu-bar shelf for the MacBook notch. It stays out of the Dock. Collapsed, it matches the notch (or a small pill on Macs without one). Drag files toward that spot, or hover it, and it springs open into a dark shelf. Drop files and folders onto it, then drag them back out to Finder or any other app.

Items are remembered across launches as bookmarks to the original files. Centik does not copy a file unless the drop came from a temporary location that would otherwise disappear.

## Requirements

- macOS 14 or later
- Xcode 16 or later (DynamicNotchKit 1.1 is a Swift 6 package)

A Developer ID or Apple Development certificate is optional. The project is set up to ad-hoc sign so it builds without a team. Launch at Login is more reliable once the app is signed with a stable identity and lives in `/Applications`.

## Run from Xcode

1. Open `Centik.xcodeproj`.
2. Wait for Swift Package Manager to resolve DynamicNotchKit, Pow, and Lottie. The first fetch needs a network connection.
3. Select the **Centik** scheme and choose **My Mac**.
4. Press Run.

There is no Dock icon. Look for the notch mark in the menu bar, or move the pointer onto the notch.

## Run from the command line

```bash
./scripts/build.sh
open build/Build/Products/Debug/Centik.app
```

`scripts/build.sh` runs `xcodebuild` for the Debug configuration and writes the app to `build/Build/Products/Debug/Centik.app`. Quit from the menu bar item, or with `killall Centik`.

## Using it

- **Hover the notch**, or drag files toward it, and the shelf opens with a spring.
- **Drop** files, folders, images, or promised files (Photos, Mail, Safari). They appear as QuickLook thumbnails with names.
- **Drag an item out** to Finder or another app. Double-click or use the context menu to open it or show it in Finder. Hover an item and click the small × to remove it.
- **Clear Shelf** in the menu (or Clear inside the shelf) takes everything off. Original files are left where they were. Copies Centik made of temporary drops are deleted.
- The shelf **closes when the pointer leaves**. **Show Shelf** in the menu pins it open until you visit it and move away.
- On a Mac without a notch, the collapsed state is a small black pill at the top centre of the built-in display (or the main display, if there is no built-in screen).

## Permissions

Centik does not ask for Accessibility, Full Disk Access, or screen recording.

| Need | Why |
| --- | --- |
| Nothing, for the shelf | Drops arrive on the drag pasteboard. Bookmarks point back at those files. The app is not sandboxed, so it can notice a file drag approaching the notch without an extra prompt. |
| Login Items approval | **Launch at Login** uses `SMAppService`. macOS may leave the item in System Settings → General → Login Items until you allow it. The menu shows **Approve in System Settings…** when that happens. |
| A stable code signature | Ad-hoc signatures from a local build can change, and macOS may refuse to keep an ad-hoc login item. Sign with your Apple Development certificate and copy the app to `/Applications` if you want login to stick. |

Temporary files (anything under the user temporary directory, or a drag scratch folder in `/var/folders`) are copied into `~/Library/Application Support/Centik/Files`. Everything else is only bookmarked. The index is `~/Library/Application Support/Centik/shelf.json`.

If a file is renamed or moved, the bookmark is meant to follow it. If the file is deleted or the volume is offline, the item stays on the shelf dimmed and marked Missing until you remove it.

## Dependencies

Resolved by Swift Package Manager, pinned to the next major version:

| Package | Product | Requirement | Why |
| --- | --- | --- | --- |
| [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) | `DynamicNotchKit` | from 1.1.0 | Notch-shaped panel, safe area, and the expand/collapse spring. On displays without a notch it uses its floating style. Maintained, MIT, macOS 13+. |
| [Pow](https://github.com/EmergeTools/Pow) | `Pow` | from 1.0.6 | Item insertion (`boing`), removal (`poof`), the drop ring (`pulse`), and hover shine / landing jump. Maintained by Emerge Tools, macOS 12+. |
| [Lottie](https://github.com/airbnb/lottie-spm) | `Lottie` | from 4.6.1 | A short burst when a drop lands (`Centik/Resources/DropLand.json`). The `lottie-spm` repo is Airbnb's small binary package so the full lottie-ios history is not cloned. SwiftUI `LottieView` supports macOS. |

SwiftUI Introspect is not used. DynamicNotchKit already exposes the panel, and a pass-through wrapper on that window is enough.

Pow's haptic effects are iOS-only. On a Force Touch trackpad, Centik uses `NSHapticFeedbackManager` for a tick when the shelf opens and when a drop lands. DynamicNotchKit's hover option deepens the shadow while the pointer is over the shelf.

## How it's put together

- `CentikApp` is an accessory app (`LSUIElement`) with a single `MenuBarExtra`: Show Shelf, Clear Shelf, Launch at Login, Quit.
- `SensorPanel` is a borderless panel the size of the hardware notch, or a 168-point pill when there is no notch. It is the hover and drag target while the shelf is closed. DynamicNotchKit hides its window in the collapsed state, so something has to stay there.
- `ShelfController` calls `DynamicNotch.expand` / `hide` with a spring (`response` 0.46 open, 0.32 close). Reduce Motion switches those to short eases and turns off the Pow flourishes.
- DynamicNotchKit sizes its panel larger than the visible shape so the notch can overshoot and shadow. `PassThroughBox` becomes that panel's content view and returns no hit outside the shelf, so the rest of the screen still receives clicks.
- A global mouse-drag monitor reads `NSPasteboard(name: .drag)`. When a file drag gets near the notch, the shelf opens before the pointer is on top of it.
- Drops accept file URLs, images (PNG, JPEG, TIFF), and `NSFilePromiseReceiver` promises. `ShelfPersistence` writes security-scoped bookmarks, with a plain bookmark as a fallback, plus the last known path.
- Thumbnails come from `QLThumbnailGenerator`, with the Finder icon shown immediately and replaced when QuickLook finishes.

## What this environment could not verify

This project was written where Xcode and the macOS SDK are not available, so it has not been compiled or run. On a Mac, build with the steps above and try:

- Hover and leave the notch, including while another app is focused.
- Drag several files from Finder, including a folder, and drag one back out.
- Drop an image from Safari or Photos (a file promise).
- Quit, relaunch, and confirm the same files are still there.
- Rename a shelved file in Finder and confirm the bookmark still opens it.
- Remove the original and confirm the item shows as Missing.
- Toggle Launch at Login and, if macOS asks, approve it in System Settings.

Known limits:

- The shelf prefers the built-in or notched display. On a desktop Mac it uses the main display.
- Copying a huge temporary folder happens on the main thread and can hitch.
- Ad-hoc signing is enough to run. Login items want a stable signature.
- The pass-through hit region is inflated around the shelf's SwiftUI frame so the notch ears stay clickable. If a future DynamicNotchKit release moves that content, the hit region may need a tweak.
