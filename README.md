# Hyprland "trusted click-through"

Custom Arch package of **Hyprland 0.56.2** with a small patch that lets
root-approved ("trusted") windows honor their **wl_surface input region** for
hit-testing on the compositor, and imports the **X11 input shape**
(`XShapeInputShape/Set`) of XWayland/Electron/DXVK overlay windows as that
region.

This is what makes see-through "layered overlay" games (e.g. `Crusaders
Quest: Hero Town`) render **and** let clicks pass through their transparent
pixels — the same behavior Omagotchi gets via layer-shell `mask`, but for
regular XWayland toplevels.

> Upstream Hyprland deliberately ignores input regions on toplevel windows
> ("we don't honor input regions on toplevels, on purpose", see hyprwm/Hyprland
> #11834), so there is no config toggle — this is a source patch.

## Status — first nearly complete version

This repo is at its **first nearly complete version** milestone: the core
overlay-game loop is verified working end-to-end on the test game.

### Working now

1. **Renders through the test game (Crusaders Quest: Hero Town)** — see-through
   rendering, click-through via the XShape input region on trusted windows, and
   no cursor teleport (the game's self-`activate()` is blocked for trusted
   overlays). Verified on class `steam_app_4126220`.
2. **Never renders on top of Quickshell** — each overlay window's render space
   is shrunk to *monitor minus the quickshell bar strip* and re-follows the
   bar whenever it moves to another edge. Implemented as a self-healing audit
   in `game-overlays.lua` (open re-audits, layer events, and a 1s repeat poll;
   any overlay game already running when the config loads is force-floated).
3. **Widget mode for idle/desktop-pet games** — a `widget = true` registry flag
   (see `game-overlays.lua.example`) keeps float + see-through + click-through
   for idle games that SIZE THEMSELVES by cursor hover, without forcing
   monitor-minus-bar geometry on them (forcing it made them jitter/bounce
   against the audit).

### Known limitations

- **Auto-focus is a little buggy in both modes** — a hovered overlay window
  (widget or regular overlay) may not be focused immediately. It's rarer on a
  regular (non-widget) launch, but happens sometimes in both. The same
  workaround kicks it into a reliable state from then on: a few manual focus
  changes. Note for later investigation.
- **Cursor warp to screen center on focus-out** — sometimes when focus changes
  from the game to something else, the mouse jumps to the center of the
  screen. Fix soon.
- **Widget mode does not auto-avoid Quickshell** — widget games are never
  resized/moved to line up with the bar. This is deliberate: many such games
  don't support dynamic resizing, and force-repositioning them against the
  bar causes the jittering effect. Trade-off: an expanded widget can
  temporarily cover the bar strip.

### Not done — roadmap

3. **Render on all workspaces** so the overlay is always available (currently
   scoped to a single workspace).
4. **Auto-register tool** to test new games out of the box — add the class,
   launch options, and validate the emitted input shape automatically.
5. **Verify and fix across the game library** — confirm the treatment works as
   intended on as many of the user's games as possible and patch the gaps.

## Confirmed working games

Games verified on this setup, in the mode they are configured in. Registered
via the [overlay-games](https://github.com/Zombie-W33D/overlay-games) tool
(live registry: `~/.config/hypr/game-overlays.lua`).

### Featured overlay (full-screen, see-through)

| Game | Window class |
| --- | --- |
| Crusaders Quest: Hero Town | `steam_app_4126220` |
| Idlemon | `steam_app_4122700` |
| Desktop Raid | `steam_app_3122460` |
| Tiny Monster Haven | `steam_app_3669020` |

### Widget mode (self-sizing)

| Game | Window class |
| --- | --- |
| Idle Waters | `steam_app_2963540` |
| Berserk B.I.T.S | `steam_app_2348540` |
| Loafing Town | `steam_app_3625210` |
| My Little Life | `steam_app_2834600` |
| Mushroom Nook | `steam_app_4211860` |
| Rogue AI: Idle Domination | `steam_app_3894900` |
| Cozy Mining | `steam_app_4283650` |
| dEscape | `steam_app_2390060` |
| The Dream Globe | `steam_app_3820130` |
| Your Big, Cute Monster Farm | `steam_app_3659410` |
| Village Tale | `steam_app_3447510` |
| Little Aviary | `steam_app_3437350` |

## Build

```bash
sudo pacman -S --needed base-devel cmake ninja meson glaze hyprland-protocols
./build.sh
```

Produces `hyprland-0.56.2-3.6-x86_64.pkg.tar.zst` (and `hyprpm-*`).

## Install / downgrade

```bash
sudo pacman -U hyprland-0.56.2-3.6-x86_64.pkg.tar.zst
```

`pkgrel` is suffixed (`3.6`) so the mainline package can always be restored
(downgrade):

```bash
sudo pacman -S hyprland        # back to upstream 0.56.2-3
```

## Trusting a window class (one-time root setup)

The compositor itself runs unprivileged — **no sudo is needed at runtime** to
use click-through. Root is only required for the one-time creation/editing of
the allowlist, which lives in a root-owned location so only root can change
which classes become click-through:

```bash
sudo tee /etc/hypr/clickthrough.conf <<'EOF'
# one ECMAScript regex per line, matched case-insensitively against WM_CLASS
steam_app_.*
EOF
hyprctl trusted-clickthrough reload
hyprctl trusted-clickthrough      # status
```

`hyprctl trusted-clickthrough reload` and the click-through enforcement itself
run with normal user privileges; root is needed for the allowlist setup and any
later edits, nothing else.

Only windows matching a rule get input-region hit-testing. Everything else is
untouched.

## How it works

| File | Change |
|---|---|
| `src/xwayland/XShapeInputRegion.cpp` | reads `XShapeGetRectangles` (INPUT first, **CLIP fallback** — Wine flips the per-pixel mask between the two kinds) on each wl surface commit of a trusted class and stores it as the surface input region (current + pending); a full-surface rect or empty mask on both kinds ⇒ reset to the compositor default; selects for `ShapeNotify` (INPUT + CLIP) so region changes without a repaint are applied immediately |
| `src/xwayland/XWM.cpp`, `src/xwayland/XWM.hpp` | drains `ShapeNotify` events (INPUT *and* CLIP kinds) from XWayland and re-syncs the input region the instant Wine reshapes (no empty-rectangle staleness, no alt-tab needed) |
| `src/desktop/view/Window.cpp` | trusted overlay can't `activate()` itself (the game spams `_NET_ACTIVE_WINDOW` when focus drifts off it → used to warp the cursor to screen center + steal focus back). User-initiated focus (hover/click on opaque pixels) uses `rawWindowFocus`/`activateWindow`, so real clicks still work |
| `src/desktop/state/ViewHitTester.cpp` | for trusted floating windows, a pointer outside the input region falls through to the windows below |
| `src/managers/TrustedClickthroughManager.cpp` | allowlist from `/etc/hypr/clickthrough.conf`, reload hook, `hyprctl trusted-clickthrough` status/reload |
| `src/debug/HyprCtl.cpp`, `src/Compositor.cpp` | command registration + startup load |

## Getting a layered-overlay game fully up (prerequisites)

The *full* effect is three clicks-and-keyboard turns of work: see-through
rendering, click-through, and the input shape to drive it. Missing any piece =
either an opaque-black game or a game you can't click through. From a blank
machine, a fresh agent needs all of the following:

### 1. This compositor build

Install it per ["Install / downgrade"](#install--downgrade) above, then trust
the game's window class per
["Trusting a window class"](#trusting-a-window-class-one-time-root-setup).

### 2. Steam (the launcher)

```bash
sudo pacman -S steam    # needs the multilib repo enabled
```

Run Steam once to create `~/.local/share/Steam`, then install the tool below.
If an overlay game fails at startup, the 32-bit Vulkan/Mesa drivers needed by
DXVK are missing (`lib32-mesa` + the vendor's `lib32-vulkan-*` /
`lib32-vulkan-drivers` set — add them with `pacman`).

### 3. GE-Proton with layered-overlay support

**Stock Proton doesn't have it.** The `WINE_LAYERED_OVERLAY*` patch (per-pixel
input shape + see-through alpha) is what makes the game emit an X input shape
at all — without it the game renders opaque/black and click-through can never
engage, regardless of this compositor. Use **GE-Proton11-6** (the verified
build) or a newer GE-Proton release carrying the same patch:

```bash
mkdir -p ~/.local/share/Steam/compatibilitytools.d
cd ~/.local/share/Steam/compatibilitytools.d
curl -fL -o GE-Proton11-6-x86_64.tar.gz \
  https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton11-6/GE-Proton11-6-x86_64.tar.gz
echo '543e3af57bb138b1be5a5b98bba4d39ca59340bfa34ec8c12144f3e16d7434ed75bd7a68eafc228b16695884629595af0905156e5227c1898f93cdbc92cb5fcb  GE-Proton11-6-x86_64.tar.gz' | sha512sum -c -
tar -xzf GE-Proton11-6-x86_64.tar.gz
rm GE-Proton11-6-x86_64.tar.gz
```

Then in Steam: **restart Steam**, open the game's *Properties → Compatibility*,
and force the compatibility tool to **GE-Proton11-6**.

> Older GE-Proton line: builds that predate the layered-overlay merge ship the
> patch in the `Proton-LayeredOverlay` fork —
> <https://github.com/thaylorz/proton-ge-custom>.

### 4. Launch options (per game)

Set these under the game's *Properties → Launch Options*:

```
WINE_LAYERED_OVERLAY_ALPHA=1 WINE_LAYERED_OVERLAY_INPUT_SHAPE=1 %command%
```

- `WINE_LAYERED_OVERLAY_ALPHA=1` — enables Wine's see-through layered-overlay
  compositing (fixes the black rendering).
- `WINE_LAYERED_OVERLAY_INPUT_SHAPE=1` — makes Wine emit the per-pixel X input
  shape that this compositor reads (`XShapeInputRegion`) and hit-tests against.
  Without it the window stays opaque to clicks.

### 5. Keep it an XWayland window

The game must stay an XWayland window (never fullscreen, no Wayland driver) so
the fill-rate and input-shape code paths apply.

### 6. Keep the overlay off your bar (optional)

By default the overlay fills the whole monitor, bar included. If your desktop
shell (e.g. the Omarchy/Quickshell bar) is a layer-shell surface, no window
can "reserve" room for it — floating windows ignore exclusive zones. The
example overlay config in `HANDOFF.md` ("Game overlay config") includes a
small Hyprland-Lua pass (see `game-overlays.lua.example`) that reads the bar
layer's live geometry
(`hl.get_layers({ namespace = "omarchy-bar" })`) and auto-sizes/offsets each
overlay window so the bar stays uncovered. It detects the bar on any edge
(top/bottom/left/right), re-applies on overlay open and bar layer
open/close, and follows interactive bar drags via a lightweight geometry poll.
The pass self-heals: the overlay is reconciled to "monitor minus the bar
strip" on open (with quick re-audits), layer changes, and a 1s repeat poll,
and any overlay game that was already running when the config loaded is
forced floating — so the config added after a launch still engages.

### 7. Add the game to the overlay config (per new game)

This is the step users miss: the overlay behaviour is per-game. The **managed
way** is the separate
[`overlay-games`](https://github.com/Zombie-W33D/overlay-games) tool (GUI or
CLI): it writes the registry entry, reloads Hyprland, and marks idle games as
widgets. **By hand**, for each new layered-overlay game register its window
class in `~/.config/hypr/game-overlays.lua`
**before first launch** (find the class while it runs with
`hyprctl clients | grep -iA25 "<game title>"`):

1. Add an `o.window({ class = "^<class>$" }, game_overlay_rules())` rule.
2. Add the same class to `is_overlay_window()` so the quickshell-avoidance
   audit tracks it.

Without these the game launches *exclusive fullscreen* (`float` unset) instead
of as a floating overlay: the see-through rendering never engages, it covers
the shell, and you get an opaque/black screen — running but invisible.

The compositor's click-through allowlist (`/etc/hypr/clickthrough.conf`) is a
one-time root setup and already matches every `steam_app_.*` class, so no
trust change is needed for Steam/Proton games. Non-`steam_app` game classes
(their own executable's class) need a line added there too.