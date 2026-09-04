# Hack Club CDN for macOS

Upload files to [cdn.hackclub.com](https://cdn.hackclub.com) straight from Finder
and get the link on your clipboard.

A small, native AppKit + SwiftUI app — no Electron, no dependencies, one
`swiftc` invocation to build. It talks to the CDN's
[v4 API](https://cdn.hackclub.com/openapi.json).

## Tools
This was a one-shot with Anthropic's Opus 5 (1M), fully done in 20 minutes. I'm very impressed...!

<br>

## Install

Grab `Hack-Club-CDN.zip` from the [latest release](../../releases/latest),
unzip, and drag **Hack Club CDN.app** into `/Applications`.

The build is ad-hoc signed and **not notarised**, so Gatekeeper will refuse it
until you clear the download quarantine flag:

```sh
xattr -dr com.apple.quarantine "/Applications/Hack Club CDN.app"
open "/Applications/Hack Club CDN.app"
```

> [!IMPORTANT]
> **Turn the Finder service on.** macOS registers new services disabled. Go to
> **System Settings → Keyboard → Keyboard Shortcuts → Services → Files and
> Folders** and tick **Upload to Hack Club CDN**. While you're there you can
> give it a keyboard shortcut.

On first launch the app asks for an API key — make one at
[cdn.hackclub.com/api_keys](https://cdn.hackclub.com/api_keys).

<br>

## Four ways to upload

| | |
| --- | --- |
| **Finder → right-click → Services** | "Upload to Hack Club CDN", on any selection. Bindable to a hotkey. |
| **Menu bar** | Drag files onto the ↑ icon. It highlights as a drop target. |
| **Dock / window** | Drag onto the dock icon, or into the window's drop zone. |
| **⌘O** | Pick files from an open panel. |

<br>

## What it does

- **Copies the link automatically** when an upload finishes, with a toast to
  confirm. Click any finished row to copy it again, or use **Copy All Links**
  for a whole batch, newline-separated.
- **Shows real progress.** Each row gets a determinate bar, a percentage and a
  spinner while bytes are going up, then switches to "Processing on the
  server…" for the gap between the last byte and the CDN's response. The menu
  bar icon shows overall percentage while anything is in flight.
- **Handles big files.** Uploads stream from a scratch multipart file via
  `uploadTask(fromFile:)`, so a multi-gigabyte drop never lands in memory.
  Three files upload concurrently.
- **Zips folders** with `ditto` before uploading, rather than failing on them.
- **Reports errors properly.** Quota, auth and validation failures surface the
  CDN's own `message` and `hint`, and every failed row gets a Retry button.
- **Shows your quota** in the footer, refreshed after each upload.

Your API key lives in `~/Library/Application Support/Hack Club CDN/config.json`
at mode `600`. It's a plain file rather than the Keychain deliberately: ad-hoc
signing changes the binary's identity on every rebuild, which would mean a
Keychain prompt every time you rebuild from source.

<br>

## Build from source

```sh
git clone https://github.com/leowilkin/hc-cdn-macos
cd hc-cdn-macos
./build.sh --install
```

That compiles, ad-hoc signs, installs into `/Applications` and registers the
Finder service. Requires Xcode's command line tools; nothing else.

| Flag | |
| --- | --- |
| *(none)* | Build for this Mac's architecture into `build/` |
| `--universal` | Build a universal arm64 + x86_64 binary |
| `--install` | Also install into `/Applications` and register the service |
| `--icon` | Re-render `Resources/AppIcon.icns` from `Tools/MakeIcon.swift` |

<br>

## Layout

| Path | |
| --- | --- |
| `Sources/AppMain.swift` | `@main`, app delegate, menu bar item, Services handler, menus |
| `Sources/CDNClient.swift` | Streaming multipart upload and `/api/v4/me`, progress via `URLSession` delegate |
| `Sources/UploadManager.swift` | Upload queue, state machine, folder zipping, clipboard |
| `Sources/UploadsView.swift` | Main window, drop zone, upload rows |
| `Sources/SettingsView.swift` | Onboarding and settings |
| `Tools/MakeIcon.swift` | Draws the app icon; run by `./build.sh --icon` |
| `Resources/Info.plist` | Bundle metadata and the `NSServices` declaration |

<br>

## Releases

Push a `v*` tag and GitHub Actions builds a universal binary, verifies both
architectures and the signature, and publishes the zip to a release.

```sh
git tag v1.0.0 && git push origin v1.0.0
```
