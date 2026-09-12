# HANDOFF — Hyprland "trusted click-through" build (CQ Hero Town overlay)

Last updated: 2026-09-11. Read `## NEXT STEPS` first. Everything through
"install + allowlist" is done except the user has NOT yet re-logged in with the
new binary.

---

## Mission
Make see-through "layered overlay" Windows games (Crusaders Quest: Hero Town,
`steam_app_4126220`, run via GE-Proton/Wine + DXVK) render AND be click-
through on Omarchy/Hyprland 0.56.2 under XWayland. Only transparent pixels
should be click-through; opaque pixels must still click.

Rendering/fullscreen is 100% done. Click-through required a **compositor
source patch**: upstream Hyprland deliberately ignores wl_surface input
regions on toplevels (hyprwm/Hyprland #11834, "we don't honor input regions on
toplevels, on purpose"). Layer-shell surfaces ARE honored (Omagotchi works via
WlrLayer.Top + mask). The game is XWayland so it can't be a layer surface —
hence the patch. Also Hyprland's xwayland never imported X11 XShape, which is
what Wine/DXVK layered overlays use for hit-testing, so the patch wires that
too.

---

## NEXT STEPS

1. User re-logs in (fresh Hyprland session) so the new
   `hyprland 0.56.2-3.1` binary runs:
   - Confirm: `hyprctl version | head -1` (should show 0.56.2 or the build)
   - Confirm installed pkg: `pacman -Q hyprland`
2. Set up allowlist if not done (root-owned = trust gate):
   ```
   sudo install -Dm0644 /tmp/opencode/ct1/clickthrough.conf.example /etc/hypr/clickthrough.conf
   hyprctl trusted-clickthrough reload
   hyprctl trusted-clickthrough        # shows rules + matched windows
   ```
3. Launch the game with (GitHub/Git profile launch options; already set in a
   previous part of the session — verify still set):
   ```
   WINE_LAYERED_OVERLAY_ALPHA=1 WINE_LAYERED_OVERLAY_INPUT_SHAPE=1 %command%
   ```
   Proton: GE-Proton11-6 at `~/.local/share/Steam/compatibilitytools.d/GE-Proton11-6`.
   Make sure window class is `steam_app_4126220*`:
   `hyprctl clients -j | grep -i class`
4. Verify behavior: move the mouse over a transparent (see-through) part of the
   overlay → click should reach the window/desktop BEHIND it. Over opaque UI
   buttons → click still hits the game.
5. Fallback debugging if clicks still don't pass through:
   - Check the window actually has an X input shape: `xwininfo -shape -id <winid>`
     (win id from `hyprctl clients` address). If "no non-rectangular shape",
     Wine isn't applying it — verify WINE_LAYERED_OVERLAY_INPUT_SHAPE is
     actually reaching the process.
   - Check `#!/run/user/1000/hypr/<INSTANCE>/hyprland.log` grep
     `TrustedClickthrough` (rules load) — the shape sync itself is silent
     except on load.
   - Try class regex widening: `sudoedit /etc/hypr/clickthrough.conf` then
     `hyprctl trusted-clickthrough reload`.
   - If the wl-surface region is getting reset every commit (SurfaceState
     pending doesn't carry `updated.bits.input`), we already write both
     `m_current` and `m_pending` in `XShapeInputRegion::syncInputRegion`, so it
     should hold. Check that the hit-tester path is hit: `windowAt` in
     `src/desktop/state/ViewHitTester.cpp`.
6. Post-reformat re-grab (user reformats soon, /home and /tmp wiped):
   - Prebuilt packages: https://github.com/Zombie-W33D/hyprland-clickthrough/releases/download/v0.56.2-ct1/hyprland-0.56.2-3.1-x86_64.pkg.tar.zst
     (+ hyprpm package next to it)
   - `sudo pacman -U hyprland-0.56.2-3.1-x86_64.pkg.tar.zst`
   - Or build from source: repo README (below).
   - Then re-add the allowlist (step 2) — the file lives only on this disk.

---

## Repo / build info

- Repo: `https://github.com/Zombie-W33D/hyprland-clickthrough` (public, gh
  authed as Zombie-W33D)
  - `main` @ `0240f83`: PKGBUILD (pkgver 0.56.2, **pkgrel 3.1**), patch
    `hyprland-0.56.2-trusted-clickthrough.patch`, `build.sh`, README.md,
    `clickthrough.conf.example`, .gitignore.
  - Tag + Release: `v0.56.2-ct1` (assets uploaded: hyprland + hyprpm pkgs).
- Build locally:
  ```
  sudo pacman -S --needed base-devel cmake ninja meson glaze hyprland-protocols
  cd <repo> && ./build.sh -f
  ```
- **Downgrade to upstream anytime:** `sudo pacman -S hyprland` (upstream pkgrel
  3 < our 3.1 ⇒ pacman offers downgrade and proceeds).
- pkgrel MUST be `integer[.integer]` format — `3.ct1` was rejected by makepkg.
  Keep it numeric-dotted (currently `3.1`).

## The patch (4 hunks + 2 new files; commit `bf0beb3`/amended, applies on
  top of v0.56.2; also carried in the repo's `.patch`):
- `src/managers/TrustedClickthroughManager.{hpp,cpp}` (NEW)
  - Loads `/etc/hypr/clickthrough.conf` = one ECMAScript regex per line,
    case-insensitive, matched against WM_CLASS. Root-owned file = the sudo-gated
    trust mechanism.
  - `load()` on compositor init (`Compositor.cpp`), on `config.reloaded`, and on
    `Event::bus()->m_events.start`.
  - `isTrusted(CWindow*)` / `isTrustedClass(string)`; `status()` enumerates
    matched windows.
  - `registerCommand(SHyprCtlCommand{"trusted-clickthrough", false, ...})`
    in `src/debug/HyprCtl.cpp`: `/reload` re-reads file, no args prints status.
- `src/xwayland/XShapeInputRegion.{hpp,cpp}` (NEW)
  - On every wl commit of a trusted-class surface
    (`CXWaylandSurface::ensureListeners` commitSurface in
    `src/xwayland/XSurface.cpp`), reads the X11 input shape
    (`xcb_shape_get_rectangles`, kind INPUT) and writes it into
    `CWLSurfaceResource::m_current` AND `m_pending` `input` + sets
    `inputIsInfinite=false`. Empty shape ⇒ leaves default (no-op).
  - xcb connection via new `CXWaylandSurface::getXCBConnection()` (CXWM
    `getConnection()` is private; CXWaylandSurface is its friend).
  - Needed `xcb-shape` added to `XWAYLAND_DEPENDENCIES` in CMakeLists.txt.
- `src/desktop/state/ViewHitTester.cpp` — `windowAt()`:
  - For trusted floating windows, if the pointer is inside the window box but
    OUTSIDE the (translated) `effectiveInputRegion()`, `continue` → falls
    through to windows below (pinned + floating loops both patched). Untrusted
    windows are completely unaffected.
- Build gotchas already solved:
  - `xcb_shape_get_rectangles` takes 3 args (conn, win, kind) — NO operation
    arg (old 4-arg form fails).
  - Reply uses accessor fns: `xcb_shape_get_rectangles_rectangles(reply)` +
    `..._length(reply)` (struct has `rectangles_len` + pad, no inline array).
  - Link: `xcb-shape` via pkg + CMake.

## Game overlay config (stable, verified)
- `~/.config/hypr/game-overlays.lua` (require'd last from
  `~/.config/hypr/hyprland.lua`). Per-window rules for class `steam_app_.*` /
  titles `*Hero Town*`.
- Final rule set used:
  `float=true, size={monitor_w,monitor_h}, move={0,0},
   suppress_event="maximize fullscreen fullscreenoutput x11configurerequest",
   sync_fullscreen=false, no_max_size=true, no_shadow=true, decorate=false,
   tag="-default-opacity", opacity="1.0 1.0"`
- Result: game opens floating 1920x1080@0,0, stays `fullscreen=0` on relaunch.
- Do NOT re-add the watchdog (`hl.on("window.fullscreen")`/`window.open`)
  snapping windows back — it broke input on the game window and was rolled
  back.
- Hyprland 0.56 dispatch is namespaced: use
  `hyprctl dispatch 'hl.dsp.window.{fullscreen,resize,move}({...})'` with
  `window="address:0x..."`. Old syntaxes fail with Lua errors. Window addresses
  change per session.

## Env facts
- Omarchy, Wayland/Hyprland 0.56.2, NVIDIA RTX 3060, monitor DP-1 1920x1080.
- sudo needs password (SUDO_NEEDS_PASSWORD) — user runs sudo commands.
- `gh` authed (repo,workflow scopes). Git pushes to GitHub can hang on big
  packs — keep repo tiny; `.gitignore` covers build outputs.
- Compositor log: `/run/user/1000/hypr/<INSTANCE>/hyprland.log`.
- OpenPets (`~/Work/openpets`) — do NOT touch; user never got it working.

## History of this build (context lost after relogin)
1. GE-Proton alpha rendering fixed the see-through rendering.
2. Config rules fixed the window jumping fullscreen; final form above.
3. Root-caused click-through: Hyprland ignores toplevel input regions (#11834).
4. Designed + built the trusted click-through patch (gated by root-owned
   allowlist), packaged as Arch package 0.56.2-3.1, published to GitHub.
5. Left off: verifying click-through after install + relogin (steps above).