---
name: build-crosswire
description: Use when building the Crosswire macOS app from the command line (xcodebuild). Packages the exact invocation that avoids the device-discovery hang, plus the relink-mtime sanity check for verifying a real rebuild happened.
---

# Building Crosswire

The canonical command-line build for the Crosswire app. Use this instead of a bare
`xcodebuild` invocation.

## The command

```bash
xcodebuild \
  -project Crosswire.xcodeproj \
  -scheme Crosswire \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -skipPackagePluginValidation \
  -derivedDataPath /private/tmp/crosswire-build \
  build
```

Run from the repo root (`/Users/nick/Documents/Projects/crosswire`). Built app lands at:

```
/private/tmp/crosswire-build/Build/Products/Debug/Crosswire.app
```

## Why these flags (do not drop them)

- **`-destination 'platform=macOS,arch=arm64'`** — REQUIRED. A bare `xcodebuild … build`
  with no destination hangs indefinitely in
  `-[DTDKRemoteDeviceConnection startServiceBrowsers]` (the device-discovery phase):
  0% CPU, no compiler children, no file writes, never reaches compilation. An explicit
  macOS destination skips device discovery. A plain "is the process alive?" watch CANNOT
  tell this hang from real work — watch for compiler procs / file writes instead, or just
  always pass the destination.
- **`-skipPackagePluginValidation`** — CrosswireKit is a local SPM dependency; this skips
  the interactive plugin-validation prompt that otherwise stalls a non-interactive build.
- **`-derivedDataPath /private/tmp/crosswire-build`** — keeps build products off the
  default `~/Library/Developer/Xcode/DerivedData` path so the running dev build is at a
  known location and rebuilds are easy to reason about.

## Relink-mtime sanity check (verify the rebuild actually happened)

`strings` CANNOT confirm a Swift change compiled in — Swift string literals don't show up
the way C literals do, so grepping the binary for a flag/constant you just added returns 0
even when it's present. Do NOT use `strings` to verify a rebuild.

Instead, trust the **link product's mtime**. The real link output is the debug dylib, not
the thin `Crosswire` launcher stub:

```bash
ls -la /private/tmp/crosswire-build/Build/Products/Debug/Crosswire.app/Contents/MacOS/Crosswire.debug.dylib
```

If its mtime is newer than your source edit, the app genuinely relinked and your change is
in the build. If the mtime is stale, the build was a no-op (cache hit) — touch the changed
source file to force a recompile and rebuild:

```bash
touch CrosswireKit/Sources/CrosswireKit/<the-file-you-edited>.swift
```

then re-run the build command above and re-check the dylib mtime.
