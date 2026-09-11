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

## Build

```bash
sudo pacman -S --needed base-devel cmake ninja meson glaze hyprland-protocols
./build.sh
```

Produces `hyprland-0.56.2-3.ct1-x86_64.pkg.tar.zst` (and `hyprpm-*`).

## Install / downgrade

```bash
sudo pacman -U hyprland-0.56.2-3.ct1-x86_64.pkg.tar.zst
```

`pkgrel` is suffixed (`3.ct1`) so the mainline package can always be restored
(downgrade):

```bash
sudo pacman -S hyprland        # back to upstream 0.56.2-3
```

## Trusting a window class (the sudo-gated part)

The allowlist is root-owned, so elevating to "click-through-trusted" requires
root:

```bash
sudo tee /etc/hypr/clickthrough.conf <<'EOF'
# one ECMAScript regex per line, matched case-insensitively against WM_CLASS
steam_app_.*
EOF
hyprctl trusted-clickthrough reload
hyprctl trusted-clickthrough      # status
```

Only windows matching a rule get input-region hit-testing. Everything else is
untouched.

## How it works

| File | Change |
|---|---|
| `src/xwayland/XShapeInputRegion.cpp` | reads `XShapeGetRectangles` (INPUT/SET) on each wl surface commit of a trusted class and stores it as the surface input region (current + pending) |
| `src/desktop/state/ViewHitTester.cpp` | for trusted floating windows, a pointer outside the input region falls through to the windows below |
| `src/managers/TrustedClickthroughManager.cpp` | allowlist from `/etc/hypr/clickthrough.conf`, reload hook, `hyprctl trusted-clickthrough` status/reload |
| `src/debug/HyprCtl.cpp`, `src/Compositor.cpp` | command registration + startup load |

## Game tip (Wine / DXVK / GE-Proton)

Launch overlay games with:

```
WINE_LAYERED_OVERLAY_ALPHA=1 WINE_LAYERED_OVERLAY_INPUT_SHAPE=1 %command%
```

The game must stay an XWayland window (never fullscreen, no Wayland driver) so
the fill-rate and input-shape code paths apply.