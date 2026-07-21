# GhostPin — instructions for Claude

## Project overview

GhostPin is a macOS menu-bar app (Swift, AppKit, pure SwiftPM — no Xcode project) that pins a live, always-on-top mirror of any window: ScreenCaptureKit streams the target window's pixels into a floating `NSPanel` that spans all Spaces and full-screen apps. "Ghost mode" makes mirrors semi-transparent and click-through. Requires macOS 14+ and the Screen Recording permission, and contains deliberately zero networking code — a core privacy promise made repeatedly in the README; keep it true.

## Architecture

- **Entry**: `Sources/GhostPin/main.swift` — plain `NSApplication` + delegate, activation policy `.accessory` (menu-bar only; `LSUIElement` in `Support/Info.plist`, bundle id `com.aadhilfarhan.ghostpin`).
- **`Sources/GhostPin/AppDelegate.swift`** — status item, dynamically rebuilt `NSMenu` (`menuNeedsUpdate`), registers the three global hotkeys, handles a `--selftest <outpath>` CLI flag that runs `SelfTest` headless instead of launching the UI.
- **`Sources/GhostPin/PinManager.swift`** — singleton owning `[PinSession]` and the global `ghostAll` flag. `toggle(windowID:)` pins/unpins; preflights `CGPreflightScreenCaptureAccess()` and resolves the `SCWindow` via `SCShareableContent`.
- **`Sources/GhostPin/PinSession.swift`** — the heart: one pinned window = one non-activating floating `NSPanel` (`.canJoinAllSpaces`, `.fullScreenAuxiliary`, cascaded to the bottom-right at ~35% source width, clamped 240–560pt) + one `SCStream` (per-window filter, 32BGRA, 30 fps cap, `queueDepth` 5, `scalesToFit`). Frames arrive on a serial queue; the IOSurface is handed to `MirrorView` on the main thread. `displayedBuffer` retains the `CMSampleBuffer` currently on screen so the capture pool can't recycle it mid-display — do not remove. Tracks the source's live aspect from each frame's `contentRect` attachment and re-snaps the panel. Also owns the corner "badge": a separate child `NSPanel` (eye = toggle click-through, ✕ = unpin) that stays clickable because a ghosted panel ignores all mouse events. Stream stop/error auto-closes the session.
- **`Sources/GhostPin/MirrorView.swift`** — `CALayer`-backed video view (`layer.contents = IOSurface`, `contentsRect` crops to the frame's valid region), hover control strip (ghost toggle, opacity slider 0.25–1.0, unpin), transient hint overlay, double-click size toggle (220pt thumbnail ↔ large), and `ResizeGripView` (drag keeps source aspect; Shift-drag frees it by zeroing `contentAspectRatio`). Talks back through `MirrorViewDelegate`, implemented by `PinSession`.
- **`Sources/GhostPin/WindowLister.swift`** — enumerates pinnable windows via `CGWindowListCopyWindowInfo` (layer 0, ≥80×60, not own PID); menu shows first 15. `frontmostWindowOfActiveApp()` backs the ⌥⌘P hotkey.
- **`Sources/GhostPin/HotKeys.swift`** — Carbon `RegisterEventHotKey` (⌥⌘ + P pin/unpin frontmost, G ghost all, U unpin all), chosen specifically because it needs no Accessibility/Input Monitoring permission.
- **`Sources/GhostPin/PermissionHelper.swift`** — Screen Recording preflight/request + guidance alert deep-linking to System Settings.
- **`Sources/GhostPin/SelfTest.swift`** — headless diagnostic: writes `preflight=`, `windows=`, `target=`, and one `frame=` result line to the given path (5 s frame timeout), then exits. Run: `open dist/GhostPin.app --args --selftest /tmp/out.txt`.
- **Packaging**: `scripts/build-app.sh` assembles `dist/GhostPin.app` by hand (binary + `Support/Info.plist` + `Assets/AppIcon.icns`) — there is no Xcode bundle target. `scripts/generate-icon.swift` regenerates `Assets/AppIcon.icns` and the README/site PNGs. `docs/` is the GitHub Pages site — a single self-contained `docs/index.html` (inline CSS, light/dark via `prefers-color-scheme`).
- **CI**: `.github/workflows/build.yml` (macos-15, build on push to main/PR). `.github/workflows/release.yml` on `v*` tag: stamps `CFBundleShortVersionString` from the tag via PlistBuddy, builds the DMG + sha256, publishes a GitHub release (`--generate-notes`), and updates the Homebrew tap `AadhilFarhan/homebrew-tap` Cask (`Casks/ghostpin.rb`) when the `TAP_GITHUB_TOKEN` secret exists.

## Commands

- `./scripts/build-app.sh` — release build + assemble `dist/GhostPin.app` (needs only Command Line Tools, not Xcode).
- `swift build -c release` — binary only.
- `open dist/GhostPin.app` — run it.
- `swift scripts/generate-icon.swift` — regenerate icon assets.
- Release = push a `v*` tag; CI does the rest. There is no test suite; `--selftest` (above) is the closest thing to an automated check.

## Workflow

- **Never commit or push directly to `main`.** Every change — bug fix, feature, docs, config — goes on its own branch and lands through a pull request, even for a single commit. The user reviews and merges PRs.
- One logical change per branch/PR. Stacked PRs are fine, but note the stack in the PR body, and remember GitHub only retargets a stacked PR to `main` if the base branch is deleted when its PR merges.

## Conventions

- Threading: SCStream callbacks hop to `DispatchQueue.main` before touching any AppKit state; UI mutation is main-thread only. Sessions guard against use-after-close with the `closed` flag.
- Plain AppKit, programmatic layout (Auto Layout constraints), no storyboards/xibs, no SwiftUI, no third-party dependencies (`Package.swift` links only AppKit, ScreenCaptureKit, Carbon) — keep it that way unless the user says otherwise.
- Comments in the sources explain non-obvious *why* (buffer retention, badge-as-child-window, Carbon-over-Accessibility); match that style, don't narrate code.

## Releasing

- Release assets must keep the stable names `GhostPin.dmg` and `GhostPin.dmg.sha256` in every release — all download links point at the permanent URL `releases/latest/download/GhostPin.dmg`.
- The app is not notarized. README installation steps (Gatekeeper "Open Anyway", checksum verify, Homebrew cask `aadhilfarhan/tap/ghostpin`) depend on this — update them if signing status changes.

## Gotchas / load-bearing constraints

- **Screen Recording grant is tied to the binary signature.** `build-app.sh` signs with a local `GhostPin Dev` identity when one exists (keeps the grant valid across rebuilds) and falls back to ad-hoc otherwise (CI, other machines). After an ad-hoc rebuild the grant is invalidated: `tccutil reset ScreenCapture com.aadhilfarhan.ghostpin`, then relaunch for a clean prompt. macOS also requires quit-and-reopen after granting.
- A ghosted panel (`ignoresMouseEvents = true`) can receive no clicks at all — any control that must work in ghost mode has to live in the badge child window, not in `MirrorView`.
- `SCContentFilter(desktopIndependentWindow:)` is what lets the mirror keep streaming a buried or other-Space window; don't swap it for a display filter.
- Ghost alpha is capped at 0.65 (`min(baseAlpha, 0.65)`) so a ghosted mirror is always visibly translucent.
- Window titles from `CGWindowListCopyWindowInfo` are empty without the Screen Recording grant — the menu degrades to app names; that's expected, not a bug.
- CI env: `GH_TOKEN`, `TAP_GITHUB_TOKEN` (release workflow); the tap update step silently skips when the latter is unset.
- This CLAUDE.md is tracked in git — edits to it go through a branch/PR like everything else.
