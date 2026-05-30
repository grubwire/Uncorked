# Session state — DXVK staged; REAL blocker is in-bottle manifest fetch (2026-05-30)

Standing constraint: **native bones, custom skin**. No user-facing strings
mention Wine / engine / wrappers / version numbers (CLAUDE.md naming rule —
overrides spec lines that mention "engine version").

## 🎯 SWG finale — two gates, both now identified (2026-05-30)

The founding goal (SWG playable in-game) has exactly two remaining gates:

1. **DXVK black screen — STAGED ✓, one launch from STOP 2.** Done this session:
   `Wine.dxvkFolder` repointed to `engineFolder/DXVK` (Wine.swift:28,
   **uncommitted→now committed**); d9vk `v1.10.3-20250511` `x64/d3d9.dll` (3.8 MB)
   + `x32/d3d9.dll` (4 MB) dropped into the LOCAL engine at
   `…/app.Crosswire.Crosswire/Engine/DXVK/{x64,x32}`; `dxvk=true` on bottle
   `1A73CA21`; app rebuilt. On next game-client launch, `enableDXVK` copies the
   d3d9 DLL in and `WINEDLLOVERRIDES=…d3d9…=n,b` activates it. **Render test is
   blocked only by the lack of game data** (gate 2). The DXVK substrate is proven
   (MoltenVK 1.4.1 works); this is genuinely one launch from STOP 2.

2. **⛔ TOP BLOCKER — manifest fetch hangs in-bottle. ROOT CAUSE CONFIRMED
   (2026-05-30).** The SWG patcher can't download the game because its manifest
   fetch never completes in-bottle (`launcherManifest.ini` stays `checksum = 0`),
   so it has the patch *count* (577) but not the *list*, and never starts the
   `.tre` download.
   - **Server is fine (World 2).** `curl https://patch.swglegends.com/manifest.php`
     from bare macOS (no auth/params) returns a full valid **94 KB JSON manifest,
     577 files, total 8,310,719,585 bytes (8.3 GB)**. Account/version-gating ruled
     out. The failure is **purely in-bottle transport.**
   - **ROOT CAUSE (record-level capture, credential-safe — the diagnosis is
     locked):** Wine's winsock **does not deliver connection-end (FIN/EOF) to a
     blocking read**, so the JVM's manifest read **hangs forever even though the
     full body arrived.** Proof on the manifest connection (Thread-6, SNI
     patch.swglegends.com):
     - **Full body received, NOT truncated:** TLS Application-Data reads summed to
       `384 + 16464×5 + 12848 + 80 + 80 = ` **95,712 B ≈ the 94,694-byte manifest
       + headers.**
     - **NOT gzip:** 95,712 ≈ *uncompressed* size (gzipped would be ~25 KB) → the
       launcher got plain JSON; nothing to fail-decode. (So "strip gzip" is moot.)
     - **Read never terminates + timeout never fires:** `setSoTimeout(5000)` set,
       but **0** `SocketTimeoutException` and **1,541× `select status 0`** (idle
       poll) over ~30 s — read blocked ~6× past its own 5 s deadline. **Wine does
       not honor `SO_RCVTIMEO`.**
   - **Cheap JVM levers EXHAUSTED:** `-Dhttp.keepAlive=false` tested clean — the
     connection *did* close (`estab→0`) but the manifest **still** stayed
     `checksum=0`. Closing the socket doesn't help because **Wine never surfaces
     the close to the JVM read.** No JVM-side knob can fix this; even if the 5 s
     timeout fired, the launcher would just get a `SocketTimeoutException` and
     still fail — the read must *terminate with the full body*, which needs Wine
     to deliver end-of-stream.
   - **This is the #2 (CLOSE_WAIT) root.** One Wine-winsock fix pays both down.
   - **THE FIX (next session — deep engine work, do NOT start cold):** a
     **Wine-source winsock/ws2_32 patch** to (a) deliver connection-end/FIN to
     blocking reads so the read returns the body, and/or (b) honor `SO_RCVTIMEO`
     so the read times out — then **engine rebuild via `engine-bundle.yml`**, same
     class as the existing `scripts/patch-cw-*.py` patches (signal/virtual/cpu).
   - Evidence files (credential-free):
     `~/Library/Logs/app.Crosswire.Crosswire/swg-manifest-STEP1-mechanism-2026-05-30.txt`
     (byte accounting + timeout/idle-poll proof) and `…-SIGNALS-2026-05-30.txt`.
     Full `ssl,plaintext` captures were DELETED — SWG sends the password
     **cleartext** in the auth POST (`un=…&pw=…`), so any plaintext capture leaks
     it; **record-level only** if re-capturing.

**Tonight's stop:** diagnosis fully locked, cheap levers exhausted. The fix is a
Wine-source winsock patch + engine rebuild — exactly the deep-engine work to do
in a fresh session, not cold late at night.

### → NEXT SESSION: Wine winsock connection-end fix (start mid-fix)
1. Research where in Wine's **ws2_32 / winsock (dlls/ws2_32, server/sock.c)** a
   blocking `recv`/`select` is supposed to return on FIN/EOF, and where
   `SO_RCVTIMEO` should fire — both are failing for the SWG manifest read.
   Compare Gcenx 11.9 vs upstream/CrossOver for a known patch.
2. Draft the patch as `scripts/patch-cw-winsock.py` (+ `scripts/patches/*.patch`),
   add its rebuild mapping to `engine-bundle.yml`'s MAPPING table, rebuild.
3. **Fast verify against the 94 KB manifest fetch** (seconds): launch javaw
   direct, login, check `launcherManifest.ini` checksum != 0. No 8.4 GB needed to
   test the fix.
4. Once it fetches: confirm the patcher BEGINS pulling the 577 `.tre` files →
   full download → **STOP 2** (DXVK already staged: launch `SwgClient_r.exe`,
   capture render).

### ⚠️ #93 crash is NOT fully fixed (2026-05-30)
The safepoint fix `3fad7e6` **reduces but does not eliminate** the #93
native-transition crash. Reproduced this session **with all safepoint flags
applied** (confirmed in the hs_err `jvm_args`): `Internal Error 0xfffffcc8`,
`ntdll.dll`, thread **`QuantumRenderer-0`** (JavaFX) in `_thread_in_native_trans`
— the same 0xfffffcc8 signature, still intermittent. **#84/#93 stay open** (and
not just for the black screen — the crash itself still recurs).

## ✅ FRESH-INSTALL validation — crash fix ships AND auto-applies (2026-05-29)


## ✅ FRESH-INSTALL validation — crash fix ships AND auto-applies (2026-05-29)

Did a **full wipe + clean reinstall** to prove the shipped fix works for a real
first-time user, not just our hand-patched bottle. Deleted the old 8.7 GB bottle
`BD247FEE` (and the 8.4 GB download with it — deliberate), cleared
`BottleVM.plist`. New bottle `1A73CA21-DC93-4B56-9F9A-D670789941DA`.

- Rebuilt from HEAD first (the running build predated `3fad7e6`), installed SWG
  via Crosswire's normal Install flow (`SWGLegendsSetup.exe`), drove the Inno
  wizard to Finish (unchecked its "Launch SWG Legends" so first launch goes
  through Crosswire, not the installer).
- **Key result — `JavaAppDetector` auto-seeded the full fix on the new bottle**
  with zero manual steps: per-program plist `_JAVA_OPTIONS` = the complete
  safepoint set (`-Dprism.order=j2d -Xint -XX:-UseBiasedLocking
  -XX:+UnlockDiagnosticVMOptions -XX:GuaranteedSafepointInterval=0
  -XX:-UsePerfData`) **+** `dwrite=builtin` override. This is what a real user
  gets on first install.
- **Launcher comes up consistently — two independent launches:** (1) Crosswire's
  post-install auto-launch and (2) the manual **Launch** button. Both rendered
  the full SWG login screen (logo, fields, Bespin art, "Ver 2.91"); javaw stable;
  **0 `hs_err` dumps** across the whole run. Login screen ≠ playable, so #84/#93
  stay open (see DXVK below).

## 🔬 DXVK black-screen — ROOT CAUSE NAILED (2026-05-29, new top engine blocker)

Diagnosed **without** re-downloading the 8.4 GB game (a runtime game capture
would be empty on the Vulkan side *by definition* — see below). Static engine
inspection + a direct MoltenVK probe:

- **MoltenVK / Vulkan / Metal WORKS.** Engine 11.9 ships `libMoltenVK.dylib`
  (x86_64, v1.4.1, Vulkan 1.4.334) and `winevulkan.so`/`.dll`. A minimal x86_64
  probe (`/tmp/vkprobe.c`) dlopen'd the engine's MoltenVK, **created a VkInstance
  and enumerated the M1 Pro GPU via Metal** (MSL 3.2, GPU Family Apple 7 / Mac 2
  / Metal 3, ~12 GB). The Vulkan→Metal substrate DXVK needs is fully functional.
  (Corrects the earlier-session assumption that the engine had no Vulkan stack.)
- **DXVK is ABSENT — from the engine entirely, not just the bottle.** No DXVK
  DLLs anywhere under the engine *or* the bottle. Bottle `d3d9.dll` is Wine's
  **builtin wined3d** (188 KB; DXVK's d3d9 is multi-MB). `dxvkConfig.dxvk=false`,
  and toggling it would do nothing — `enableDXVK` has no DLLs to copy.
- **Therefore the black screen:** `SwgClient_r.exe` (D3D9) has no path to the
  working Vulkan/Metal stack, so it falls back to **wined3d → opengl32 → winemac
  → AppleMetalOpenGLRenderer** (Apple's deprecated GL-over-Metal) → black.
- **Why no runtime game capture was needed:** without DXVK installed the game
  never touches Vulkan, so `WINEDEBUG=+dxvk/+vulkan`, the DXVK HUD, and DXVK
  logs are all empty. The MoltenVK probe gives the Vulkan/Metal evidence the
  game path *can't*. (User accepted this as the engine-task input, skipping the
  re-download.)
- **Fix (next session, scoped):** bundle a MoltenVK-compatible DXVK into the
  engine (so `enableDXVK` has source DLLs), enable `dxvkConfig.dxvk`, relaunch.
  The fix is **viable** — the Vulkan→Metal target is proven working; DXVK is
  simply not shipped. Engine note: the sandboxed engine lives at
  `~/Library/Application Support/app.Crosswire.Crosswire/Engine/` (not the bare
  `…/Crosswire/Engine` in CLAUDE.md — sandbox container path).

### → NEXT SESSION: DXVK bundling brief (do NOT start now — its own fresh session)

This is **engine build-pipeline** work (CI/YAML/signing), a different domain
from the app's Swift — start it fresh with research up front, not as a tail of
this session.

**The fix:** bundle a MoltenVK-compatible DXVK into the engine via
`.github/workflows/engine-bundle.yml`, so the engine archive ships DXVK DLLs that
`enableDXVK` can copy into a bottle. This is **not** a local one-off — it goes
through the **full engine re-version → sign → promote-to-prod cycle**:
`engine-bundle.yml` (build + `sign-engine.sh` ad-hoc Mach-O signing + smoke test
+ signed manifest, no auto-publish) → human test the artifact → `engine-promote-prod.yml`
(upload archive to R2 `engine/prod/archives/`, then overwrite the signed manifest)
→ bump `engine-version.txt`. Note: DXVK ships PE `.dll` files (NOT Mach-O), so
`sign-engine.sh` skips them — but they must land in the archive tree where
`enableDXVK` looks. **Blocked on Checkpoint D** (R2 not yet stood up) for actual
prod promotion; can be built + locally tested before that.

**Proven inputs (from this session):** engine 11.9 already has the Vulkan→Metal
substrate — `libMoltenVK.dylib` (x86_64, v1.4.1, Vulkan 1.4.334) + `winevulkan`;
probe enumerated the M1 Pro GPU via Metal. So DXVK only needs to be *added*; the
target it renders to is confirmed working.

**Open questions to research first:**
1. **Which DXVK build is MoltenVK-compatible?** MoltenVK doesn't support every
   Vulkan feature DXVK assumes — need a DXVK release/fork known to work on
   MoltenVK (e.g. DXVK-macOS / the CrossOver/Gcenx-style build), matching the
   engine's Vulkan 1.4.334 / MoltenVK 1.4.1 and **x86_64** (engine is x86_64 Wine
   under Rosetta — DXVK DLLs are PE, but verify the targeted GAPI/arch).
2. **How DXVK gets enabled per-bottle.** There's an existing `dxvkConfig.dxvk`
   setting + an `enableDXVK(bottle)` that copies DXVK `{x64,x32}` DLLs into
   system32/syswow64. Confirm/wire it to also set a **`d3d9=native,builtin`
   DLL override** (DXVK provides d3d9; mirror the `dwrite=builtin` override
   pattern `JavaAppDetector` already uses). Decide whether SWG bottles auto-enable
   DXVK (it's a D3D9 game) or it's user-toggled.
3. **Promotion sequence / safety** — re-confirm the archive layout
   `enableDXVK` expects (`<libraryFolder>/DXVK/{x64,x32}`), and that adding DXVK
   doesn't change `engine-manifest.json` schema (just a new file set + new
   version). Roll-forward only; prior archives retained for rollback.

## ✅ DXVK research — STOP 1 findings (2026-05-30, investigation only)

Answered the three open questions before any build. Three curveballs caught
cheaply — read these before starting the build phase.

### Q1 — Which DXVK build (CURVEBALL: the obvious one dropped D3D9)

**SWG is a D3D9 game** (2003-era; SwgClient_r.exe renders via D3D9 → that's the
exact wined3d→AppleGL path that black-screens). So we need a **D3D9** Vulkan
translator, not D3D10/11.

- ❌ **Gcenx/DXVK-macOS** (the upstream-matching fork) — latest is v1.10.3
  (2024 repack) and it **explicitly removed `d3d9.dll`** ("shouldn't be used on
  macOS"); it's D3D10/11 only. **Unusable for SWG.**
- ✅ **RECOMMENDED: `Sikarugir-App/d9vk`, release `v1.10.3-20250511`**
  (async, D3D9-only, macOS-built, May 2025). Sikarugir-App is the *currently
  active* (2026) macOS-Wine gaming toolchain (they also maintain a MoltenVK
  fork, winetricks, a `dxvk` D3D9/10/11 source repo, and Metal-path `dxmt`/`d9mt`).
  - Downloaded + inspected the tarball: layout is `x64/d3d9.dll` (PE32+ x86-64,
    3.8 MB) + `x32/d3d9.dll` (PE32, 4 MB) + `dxvk.conf`. The **`x64/`+`x32/`
    folder names exactly match what `enableDXVK` already expects** — drop-in.
  - DXVK **1.10.3** base needs only ~Vulkan 1.1 + a handful of extensions →
    far lower bar than DXVK 2.x (which needs Vulkan 1.3 + dynamic_rendering etc).
  - It's an **async** fork → honors `DXVK_ASYNC=1`, which Crosswire already sets.
- **MoltenVK compatibility CONFIRMED against the engine's own MoltenVK 1.4.1**
  (re-checked the probe's 153-extension dump): `VK_EXT_robustness2`,
  `VK_KHR_dynamic_rendering`, `VK_EXT_extended_dynamic_state` 1/2/3,
  `VK_KHR_maintenance*`, `VK_EXT_vertex_attribute_divisor` all **PRESENT**.
  Absent: `VK_EXT_graphics_pipeline_library` (DXVK falls back to sync pipeline
  compile — more stutter, still works) and `VK_EXT_transform_feedback` (D3D9 is
  largely fine without; matters mainly for D3D10/11 geometry/stream-out).
  - These are the very extensions DXVK-macOS was *waiting on MoltenVK for* in
    2023 — MoltenVK 1.4.1 now provides them, so the 2023 blocker is resolved.
- **Fallback if d9vk-on-MoltenVK still black-screens:** Sikarugir's `d9mt`
  (D3D9→**Metal** directly, no MoltenVK). Different engine integration (needs
  DXMT's Metal runtime, not our Vulkan path) — only pursue if Vulkan path fails
  at STOP 2.

### Q2 — Per-bottle enable (GOOD NEWS: app side is already wired)

The DLL-override is **already implemented** — and via env, not the registry:
- `BottleSettings.environmentVariables` (BottleSettings.swift:322) sets
  **`WINEDLLOVERRIDES=dxgi,d3d9,d3d10core,d3d11=n,b`** (native,builtin) whenever
  `dxvk == true`, plus `DXVK_HUD` and `DXVK_ASYNC=1`. (This is the DXVK analogue
  of the `dwrite=builtin` registry override — env-based, so it auto-reverts when
  the toggle is off; no registry residue.)
- `Wine.enableDXVK(bottle:)` (Wine.swift:559) copies `{x64,x32}` DLLs from
  `Wine.dxvkFolder` into system32/syswow64 via `replaceDLLs`. Called lazily at
  launch in `runProgram` (Wine.swift:144) and `runInstaller` (:221) when
  `bottle.settings.dxvk` is true.
- The Advanced **"DXVK (DirectX to Vulkan)" toggle** (EntryDetailView.swift:228,
  ConfigView.swift:121) just binds `bottle.settings.dxvk`.
- **So: NO app-code change is needed to wire the override.** The only thing
  missing is the DXVK DLL *files* for `enableDXVK` to copy.
- **CURVEBALL (the one code change required):** `Wine.dxvkFolder` =
  `CrosswireEngine.libraryFolder/DXVK` = `…/app.Crosswire.Crosswire/`**`Libraries`**`/DXVK`
  — a **sibling of `Engine/`, NOT inside the engine archive** (engine-bundle.yml
  packs `engine/` → installs to `…/Engine`; it never writes `Libraries/`). So if
  we bundle DXVK *into the engine archive*, `enableDXVK` won't find it. Resolve
  by **one of**:
  - (A, recommended) change `Wine.dxvkFolder` to a path *inside* the engine
    (e.g. `engineFolder.appending("DXVK")`) — 1-line Swift change — and have
    engine-bundle.yml drop d9vk into `/tmp/engine/DXVK/{x64,x32}`. DXVK then
    ships, versions, signs, and installs atomically with the engine; fresh
    installs get it automatically. (sign-engine.sh signs Mach-O only and skips
    the PE d3d9.dlls — correct, they're Windows DLLs.)
  - (B) keep `Libraries/DXVK` and deliver DXVK via a separate download/install
    step (own manifest/object). More moving parts; doesn't ride the engine's
    signed manifest. Not recommended.
- Minor: toggling DXVK *off* after on leaves the copied DXVK DLLs on disk, but
  without `WINEDLLOVERRIDES=native` Wine uses its compiled-in builtin d3d9 → no
  functional effect. A `disableDXVK` restore path is a nice-to-have, not a
  blocker.

### Q3 — Promote-to-prod sequence + blockers

Pipeline (all manual, human-gated — see CLAUDE.md):
1. **`engine-bundle.yml`** (workflow_dispatch, `force=true` required — Gcenx 11.9
   already == `engine-version.txt`, so the gate skips without force): fetch Gcenx
   → extract to `/tmp/engine` → wrappers → patch/rebuild ntdll/wow64cpu/wineserver
   → **[NEW STEP: drop d9vk into `/tmp/engine/DXVK/{x64,x32}`]** → `sign-engine.sh`
   (Mach-O only; **skips DXVK PE .dlls — correct**) → boot smoke test →
   **measure size** (`du -sk` of `/tmp/engine` — DXVK is counted automatically if
   added before this step) → repack `engine/` as tar.xz → **sha256** →
   `engine-manifest.json` (schemaVersion/engineVersion/upstreamTag/url/sha256/
   sizeBytes/minAppVersion) → `sign-manifest.sh` (Ed25519) → upload artifact
   (no auto-publish).
2. Human tests the artifact locally.
3. **`engine-promote-prod.yml`** (inputs: engine_tag + bundle run_id): downloads
   artifact → uploads archive to R2 `engine/prod/archives/` → overwrites
   `engine/prod/engine-manifest.json` + `.sig` → bumps `engine-version.txt`.
- **BLOCKER 1 — Checkpoint D not done.** Prod promotion needs R2 stood up:
  bucket + `data.grubwire.io` custom domain + secrets `R2_ACCOUNT_ID`,
  `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`, and
  `ENGINE_MANIFEST_SIGNING_KEY`. Until then **Phase 3 (prod promote) cannot
  run** — but local bundle + local test (Phase 2) is unblocked.
- **BLOCKER 2 — versioning gotcha for existing installs.** `shouldUpdateEngine`
  (CrosswireEngine.swift:237) updates only when `local < remote` engineVersion,
  and the manifest's `engineVersion` = the bare Gcenx tag ("11.9"). Re-bundling
  11.9 with DXVK keeps engineVersion "11.9" → **existing 11.9 installs would NOT
  pull the DXVK engine.** Need a Crosswire-side revision scheme (e.g. "11.9.1")
  decoupled from the Gcenx tag, which means a small engine-bundle.yml change to
  set engineVersion independently of upstreamTag. **Fresh installs are
  unaffected** (first-run downloads whatever the manifest says) — so STOP 3's
  fresh-install test works regardless; only the existing-user update path needs
  this.

### Phase 2 heads-up — SWG game files were wiped
Reaching the 3D render path needs SWG's installed game data, which we deleted
with bottle `BD247FEE` (rm -rf, not Trash — **not recoverable**). Phase 2 local
test will need a **re-download of the ~8.4 GB** (with the known CLOSE_WAIT
stall→restart pattern). The launcher gates "Play" behind a complete 571-file
patch, so a partial install likely won't reach the client. Report the chosen
path before burning hours.

## 🛠 Build gotcha — xcodebuild -destination fixes a rebuild hang (2026-05-29)

A bare `xcodebuild -scheme Crosswire -configuration Debug -derivedDataPath …
build` **hung indefinitely** in `-[DTDKRemoteDeviceConnection startServiceBrowsers]`
(device-discovery phase) — 0 % CPU, no compiler children, no file writes, never
reached compilation. Adding an explicit destination fixes it:
`-destination 'platform=macOS,arch=arm64'` (also pass `-skipPackagePluginValidation`).
Use this for all future rebuilds. A plain "process exists" watch can't tell this
hang from real work — watch file-writes/compiler-procs instead.

## ✅ SWG launcher crashes FIXED (#84/#93) — in-game pending DXVK (2026-05-29)

The SWG launcher's login crash (#84) and patcher crash (#93) are **fixed**
(`3fad7e6`) — login, content, and the full 8.4 GB game download all work with
zero crashes. **In-game render is not yet confirmed** (the game client launches
but shows a black screen — DXVK blocker; see "In-game attempt" below). So the
crash class is solved; keep #84/#93 open until you can actually play. The root cause was **not** Wine networking, certs, or a Wine-fork
gap we had to patch — it was a **JVM↔Wine thread-suspension bug**: HotSpot
crashes with `Illegal threadstate encountered: 6` (`safepoint.cpp:712`), and
faults in Wine's `ntdll`, when it suspends a thread mid native↔VM transition to
reach a safepoint. It hit hardest on the launcher's **network/Finalizer
threads** closing TLS connections — which is exactly why content/patch-check
appeared to "hang on the network" (connections in `CLOSE_WAIT`) and the patcher
died ~392 MB in. (TLS itself was always fine: 14 successful handshakes, no cert
errors; the cacerts even has ISRG Root X1.)

**Fix:** extend the seeded `_JAVA_OPTIONS` for bundled-JRE launchers to suppress
the avoidable safepoints — `-XX:-UseBiasedLocking`,
`-XX:+UnlockDiagnosticVMOptions -XX:GuaranteedSafepointInterval=0`,
`-XX:-UsePerfData` (in `JavaAppDetector.recommendedJavaOptions`; also written
into the SWG bottle's per-program plist so it applies now).

**Verified live:** login works → launcher content + news load → "Update"
becomes available → patcher downloads **past 1.8 GB** with zero crashes (it
died at ~392 MB before). How we found it: `javax.net.debug` capture (via a
shell launch with stderr→file, since the JVM does its own TLS, not Wine's
schannel) caught the fatal safepoint error firing on the URL-Loader/Finalizer
threads. Follow-ups: minimize the flag set, verify/close the GitHub issues.

## Shipped (all on `origin/main`)

**Task D — redesign (prior session):** spec amendments `8a67081`; accent
`cf35f24`; native toolbar `08967c3` (+ icon fixes `d6af693`, `3a24689`);
contained library + rows `e937c13`; row redesign + context menu `a86fa7e`;
inline detail + native Settings sidebar + materials `5ee41dd` (+ accent-bar
drop `0ad8662`); single-instance + a11y `fc0768b`; labeled "+ Install"
affordance `7f567c9`; Task-D doc `4006c3f`.

**This session (redesign-loop cleanup):**
- `1c8d18e` — **dead-code removed**: deleted `AppSettingsSheet.swift` +
  `SettingsView.swift` and their pbxproj entries (superseded by
  `EntryDetailView` / `InlineSettingsView`). Build green.
- `c2f67e5` — **Settings content cleanup**: real General (App Data Location
  with Show in Finder + Change…, no raw container path), Updates (second
  toggle relabeled "Windows compatibility updates" — no "engine" string,
  still its own key), About (icon + version + GitHub / Website / Report-an-
  Issue links; dropped the engine-version line). Replaced the thin shim
  group-views with finished content.

Theme tokens: `rowSurface`, `rowSurfaceHover`, `regionBorder`,
`Typography.sectionHeader`. All built clean and runtime-checked.

## Decisions worth remembering
- **Install affordance**: labeled "+ Install" toolbar button (blue primary,
  `.titleAndIcon`), suppressed when the library is empty (hero CTA is the
  single target there). Intentional — don't native-correct to a bare icon.
- **Sidebar selection**: native `.sidebar` blue pill, no custom accent bar.
- **No user-facing engine/version strings** anywhere (Updates toggle, About,
  detail Advanced all comply). NOTE: `DiagnosticsView` still has a
  `Section("Engine")` — diagnostics is developer-facing but worth a sweep.
- **Omitted on purpose**: "Change Icon…" (no backing), DLL-overrides editor
  (none exists), engine version in detail/About. Don't ship empty editors.

## "Launch re-runs the installer" — MISDIAGNOSED, not a Crosswire bug (2026-05-29)

Investigated and **cleared**. Last session I saw a `SWGLegendsSetup.exe`
process and inferred Crosswire's Launch ran the installer. Three independent
lines of evidence show that's wrong — Crosswire resolves/launches the correct
installed launcher every time:
1. Bottle `BD247FEE`'s persisted `primaryProgramURL` is the launcher
   (`…/SWG Legends/SWGLegendsLauncher.exe`), not the installer.
2. All five recent run logs show `start /unix …/SWGLegendsLauncher.exe`.
3. `updateInstalledPrograms` enumerates only `drive_c/Program Files[ (x86)]`
   inside the bottle, so `~/Downloads/SWGLegendsSetup.exe` can't ever be in the
   list `runPrimary` chooses from.

The `SWGLegendsSetup.exe` process was either a stale leftover from a prior
launcher run, or the SWG launcher's own child — the launcher re-invokes its
Downloads bootstrapper because the game is **not fully installed** (SWG dir is
only ~237 MB: launcher + a few patch `.tre` files + `hs_err_pid228.log`, the
#93 crash dump). That's downstream of #93 (patcher crash leaves the install
incomplete), not a primary-resolution bug. **No Crosswire fix needed here.**

## Single-instance — needs its own pass

Shipped (`fc0768b`) but **currently inert** (safe). Verified at runtime:
`Wine.runningProcessIDs` matches `WINEPREFIX=<prefix>` in `ps -E`, but macOS
**hides the environment of Crosswire's detached `wine start /unix` processes**
from `ps` (`ps -E -p <pid>` shows command only). So detection returns empty →
the guard never fires → it always falls through and spawns. The self-healing
design means launches are NOT broken, just un-deduped.

- **Lead fix candidate: match by argv, not env.** The wine process's argv IS
  visible (`Z:\…\X.exe` / `C:\Program Files…\X.exe`) even when env isn't. Map
  the bottle's program URL → its Windows path/basename and match.
- **Weak spot that approach must solve:** basename collisions across bottles
  (two bottles with the same exe name). Needs to disambiguate (e.g. full
  Windows path, or correlate with the launched program), not just basename.
- Confirming winemac.drv GUI apps surface as `NSRunningApplication` with
  `.regular` policy is still unverified (the installer, not a GUI app, was
  what launched during the test — see the bug above).

## Observability state (diagnosed 2026-05-29)

- **Local logging: yes.** Each wine launch writes a timestamped file to
  `~/Library/Logs/app.Crosswire.Crosswire/<ISO8601>.log` (`Wine.makeFileHandle`):
  app + bottle header, process info (args/exe/cwd/env), then every stdout
  (`Logger.wineKit.info`) and stderr (`.warning`) line + the exit status.
  Dual-logged to os.log (Console.app). Logs auto-pruned after 7 days.
- **Crash surfacing:** `FailureWatcher` shows a "stopped unexpectedly" dialog
  (Report… → prefilled GitHub issue with log + engine version + bottle config /
  View Log / Not Now) on `crosswireProgramDidExit` when `isAbnormal`
  (`exitCode != 0`), debounced 30s/exe. **Manual reporter, not telemetry.**
- **⚠️ The gap that matters:** launches use detached `wine start /unix`. The
  captured process is the `start` invocation, which exits ~immediately (status
  0) after handing off to wineserver; at that point `drainPipesAtTermination`
  clears the readers and **closes the log handle**. So the per-run log captures
  only the launch + first seconds — the long-running app's later output
  (crash-time Wine/JVM stderr) is NOT captured, and FailureWatcher never fires
  (start exited 0). **GUI-app crashes (#84/#93 class) are invisible to
  Crosswire's own logs** — the only crash evidence is the JVM's `hs_err_pid*`
  dumps written into the bottle dir.
- **Sentry: not wired** (zero references; no dependency). The Privacy pane's
  "crash reporting in a future release" is pure placeholder text.
- **Notifications: pure placeholder.** The bell is a non-functional button; no
  event model, store, or view behind it.

## Brief 1 — engine diagnostics findings (2026-05-29)

Exercised the `captureDiagnostics` path (built `91998ab` + `c9ffd6f`) against
SWG for the first time. Results:

- **The capture path does NOT work for SWG (or any re-exec'ing launcher).**
  `SWGLegendsLauncher.exe` is a stub that re-execs as a *detached*
  `javaw.exe -jar … (ppid=1)`. The direct-`wine` foreground process exits at
  ~5s when the stub forks javaw, so the per-launch log closed with **only the
  794-byte header — zero app output**, and `presentDiagnostics` fired at that
  5s stub-exit, long before any crash. Same blind spot as `start /unix`, just
  moved to "stub exits". **This is the thing to fix.**
  - Achievable fix: don't end the diagnostics run at foreground-process exit —
    **poll until the bottle is idle** (no wine procs for the prefix), *then*
    scan for + reveal `hs_err_pid*.log`. Delivers the JVM crash dump (the real
    #84/#93 evidence) reliably even without live stdout.
  - Hard part (defer): live stdout/stderr of detached, re-exec'd Wine children
    across the wineserver boundary — same class of problem as the original.
- **SWG install is incomplete** (237 MB: launcher + bundled JRE + 2 patch
  `.tre` fragments; no base game data). Launcher runs; game never downloaded.
- **#84 is currently worked around.** With `dwrite=builtin` + `prism.order=j2d`
  + `-Xint`, **login SUCCEEDS** (verified live — reached the post-login screen,
  "Update Required — 571 patches"). The reachable crash is #93 (the patcher),
  which needs the full multi-hundred-MB download (not driven — long + corrupts
  state, and the capture path can't catch it anyway).
- **Crash read (from `hs_err_pid228.log`, the real on-disk data):**
  `EXCEPTION_ACCESS_VIOLATION` at **`ntdll.dll+0x52070`** (Wine builtin ntdll),
  near-null deref (`ecx=0x107`), on a daemon thread `_thread_blocked_trans`,
  **during a JVM safepoint** (VM `synchronizing`; VMThread holds
  `Safepoint_lock`+`Threads_lock`). Loaded: glass/dwrite/opengl/**wined3d**
  (no DXVK). **This signature matches neither documented issue** (#84
  `pc=0x7bf2800b` BitSet.equals; #93 `pc=0xfffffcc8` vtable) — it's a third
  signature: a Wine-ntdll fault during JVM thread-suspension for a safepoint.
- **Leading fix direction for #84/#93:** Wine-fork ntdll thread-suspension /
  SEH gap (NtSuspendThread / NtSetContextThread / exception dispatch) —
  CrossOver-patches-vs-Gcenx-11.9. **Not** app-level, **not** DXVK/Vulkan,
  **not** Crosswire config (env/plist/dwrite all correct; login works).
  Engine-level effort; out of scope per the brief.

## In-game attempt + remaining blockers (2026-05-29)

Drove the full path: download → install → launch the game client.

- **Download completed: 8.4 GB, 202 `.tre`, `SwgClient_r.exe` present.** The
  crash fix held the whole way — **0 new `hs_err` dumps** across a 12 hr
  download and the client launch.
- **Stall pattern (feeds the winsock self-recovery task):** one genuine
  mid-download stall at **4382 MB (file 361/571)** — connections dropped to
  `CLOSE_WAIT`/`CLOSED`, size flatlined, the patcher hung (its blocking read
  never returned because Wine's winsock doesn't signal the dropped FIN). **One
  restart** (kill → relaunch → re-login → Update) resumed it; it then ran to
  completion. (A second apparent "stall" at 8577 MB was just the patcher idle
  at *done* — re-login showed "Ready to play".) So: **1 stall, 1 restart**.
- **Crosswire awareness: good** — bottle `primaryProgramURL` = the launcher
  (correct: Launch runs the launcher → Play runs the client); `drive_c` now
  contains `SwgClient_r.exe` so `updateInstalledPrograms` sees it; library row
  shows "Star Wars Galaxies Legends".
- **⛔ BLACK SCREEN blocker (SUPERSEDED — see "🔬 DXVK black-screen — ROOT CAUSE
  NAILED" near the top, which is authoritative: DXVK is absent from the *engine*
  itself, not just `Libraries/DXVK`, and MoltenVK is proven working via direct
  probe).** Clicking Play
  launches `SwgClient_r.exe` and it **runs without crashing** (so the crash fix
  carries into the client), CPU ~5%, but the window stays pure black (no
  loading/login/world; focus+Enter+Space did nothing). Root cause: the client
  renders D3D9 via **wined3d → `opengl32` → `AppleMetalOpenGLRenderer`**
  (macOS's deprecated GL-over-Metal) — a known black-screen path. **DXVK is off
  AND not installed** (`dxvkConfig.dxvk = false`; `Libraries/DXVK` is empty —
  only Wine's own `d3d9.dll` exists; `enableDXVK` would fail on a missing DXVK
  folder). MoltenVK/Vulkan itself initializes fine in-process, so the fix is to
  **bundle/install a MoltenVK-compatible DXVK and enable it** (D3D9 → Vulkan →
  MoltenVK → Metal). This is a real engine/setup task, not a toggle — its own
  focused effort.

## Next-session queue (priority order)
(Done this session: capture-path fix `72f07be`; SWG #84/#93 crash fix `3fad7e6`;
SWG fully downloaded + game client launches with no crash.)
1. **DXVK for the game client (THE top blocker — root cause nailed, see "DXVK
   black-screen" above).** DXVK is absent from the engine; MoltenVK/Vulkan/Metal
   is proven working. Bundle a MoltenVK-compatible DXVK into the engine so
   `enableDXVK` has source DLLs to copy, enable `dxvkConfig.dxvk`, relaunch
   `SwgClient_r.exe`, confirm it renders past the black screen. **Requires
   re-downloading the 8.4 GB game** (wiped this session) to reach the client —
   factor that into the session. Until in-game render is confirmed, **do NOT
   close #84/#93**.
2. **Winsock CLOSE_WAIT self-recovery** (engine task) — a dropped connection
   leaves the JVM's socket read blocked forever (Wine doesn't deliver the FIN),
   so the patcher hangs instead of retrying. Fix so dropped connections resume
   without a manual launcher restart (candidates: a Wine winsock/registry
   timeout, JVM `sun.net` socket-read timeouts, or a patcher watchdog).
3. **Minimize the safepoint flag set** — `3fad7e6` ships the full working combo;
   confirm which are load-bearing (likely `-XX:-UseBiasedLocking`).
4. **Single-instance / wineprefix cleanup pass** — argv-matching, basename
   collisions, `.regular` focus. **Also: orphaned-process pileup.** This session's
   wipe→install→2 launches left **~22 stale `winedevice`/`services.exe`** procs
   (reparented to PPID 1 when their wineservers died); cleaning them needed
   `ps | grep system32 | awk '{print $1}' | xargs -n1 kill -9` (multi-PID
   `kill` and tight `for` loops silently no-op'd on these). Crosswire should
   reap a bottle's prefix procs on app/bottle exit so they don't accumulate
   (ties into the single-instance work — same process-lifecycle gap).
5. **Light mode**; minor `DiagnosticsView` "Engine" wording; (optional)
   diagnostics live-stdout capture of detached children.

## Design direction (note, NOT a task)
Future: a **health-check / remediation system** that auto-recovers from known
failure modes (e.g. detect a download stall → auto-restart the launcher and
resume). Build it **per-rule, only after each failure is fully diagnosed** — a
remediation that fires on a misunderstood signal is worse than none. First
candidate: download-stall auto-restart, pending the winsock CLOSE_WAIT
diagnosis (#2 above).

## Out of scope (designed-for, not built)
Notifications panel (bell placeholder), What's New panel (sparkle
placeholder), background-install rework, icon extraction, Sentry.

## Open issues
- **#84 / #93 — crash fix CONFIRMED to ship + auto-apply, NOT yet closed.** The
  JVM safepoint flags (`3fad7e6`) fix the launcher crashes, and a **fresh clean
  install** proved `JavaAppDetector` auto-seeds them for a real first-time user
  (login screen renders on both launch paths, 0 crashes). **Keep open** until
  in-game render is confirmed — root cause of the black screen is now nailed
  (DXVK absent from engine; MoltenVK works), fix is queue #1. Don't close until
  you can actually play. (#90 and #92 closed earlier.)

## Repo state
- Branch `main`. This session: **fresh-install validation** (no code change —
  wipe + reinstall on a rebuilt-from-HEAD app), **DXVK root-cause diagnosis**
  (static + MoltenVK probe, no game re-download), **xcodebuild -destination**
  build-hang fix, this doc. Prior session shipped the SWG crash fix (`3fad7e6`)
  + capture-path fix (`72f07be`).
- Old bottle `BD247FEE` (8.7 GB) **deleted**; new validated bottle
  `1A73CA21-DC93-4B56-9F9A-D670789941DA` (~516 MB, launcher only — game NOT
  re-downloaded). `dxvkConfig.dxvk=false` (DXVK not in engine; nothing to copy).
- All wine procs cleaned up at end of session (0 remaining).
- Running dev build: `/private/tmp/crosswire-build/...Debug/Crosswire.app`,
  rebuilt from HEAD this session (relinked 19:46) — includes the safepoint fix.
- CI: green through `cf4648c` (prior); confirm on this doc's commit.
- Working tree clean after the SESSION-STATE commit lands.
