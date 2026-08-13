# CLAUDE.md

## What this repo is

A hyprlock lock screen with Monika's Act 3 dialog: the line types out, wraps inside the box and garbles on a glitch. Two halves — a config hyprlock renders, and `ddlc-hyprlock.sh`, the engine that writes the frames its labels `cat`

The seam in `rokokol/huix` is `home-manager/desktop/hyprland/services/hyprlock.nix` (`ddlc.hyprlock.enable`, the `Doki` font, `screenShader`); `services/hypridle.nix` reads `ddlc.hyprlock.lockCommand`, and the laptop sets `ddlc.hyprlock.dialog = false`. **Every lock path goes through `loginctl lock-session`** — the engine has to be hyprlock's parent, so nothing may call `hyprlock` directly and no bind may call the engine

## Build / check

```sh
nix build                # the packaged engine and its config
nix flake check          # tests, dist/ current, conf shape, module wiring, shell lint
./tests/run.sh           # the engine against stubs; --update rewrites the goldens
./tests/live.sh          # the rendered config through the real hyprlock, without locking
PREFIX=$PWD/out ./install.sh
nix fmt -- --ci
```

## Layout

```
nix/config.nix       the whole lock screen as data: geometry, colours, labels
nix/render.nix       that attrset -> hyprlock.conf, for the consumers Home Manager cannot serve
nix/                 package.nix, module.nix, module-test.nix
ddlc-hyprlock.sh     the dialog engine
assets/              the background, the dialog box, and what she says
shaders/glitch.frag  the flash, for the mode that needs no dependency
dist/                the rendered config, committed for consumers without Nix
tests/               run.sh, live.sh, the stubs and the goldens
install.sh           for systems without Nix
```

## Things that will bite

- **the text width travels back out.** `nix/config.nix` computes the geometry and hands the text area's width to the engine, which wraps at exactly that number. Change one and the other has to follow, or the line creeps out of the box
- **never signal hyprlock.** Its `SIGUSR2` handler walks the timer vector without the mutex and allocates inside the handler; a push into a busy locker wedges it. The labels poll their files instead
- **`$out` cannot travel through `writeText`.** The placeholder is only substituted in the derivation whose environment holds it. Render with `@token@` and `substitute --subst-var-by` in `installPhase` — the same token then survives into `dist/` for the non-Nix install
- **the package argument is `withDialog`, not `dialog`.** `callPackage` fills any argument that has a same-named attr in nixpkgs, silently: `dialog ? true` became `pkgs.dialog`. The public option keeps the short name
- **`&` in `${s//pat/repl}` means "what matched"** since bash 5.2, so `${s//</&lt;}` yields `<lt;`. Escaped as `\&`, which is why the engine needs bash ≥ 5.2

## Changing a colour

It comes from `ddlc-palette` via `lib.bare`, never a literal in `nix/config.nix`. Regenerate `dist/` after any change (`nix build .#dist`), or `dist-is-current` fails; the weekly `palette-drift.yml` re-renders against the palette's HEAD

## CHANGELOG

Every user-visible change adds a bullet under `## [Unreleased]` in `CHANGELOG.md`. A release moves those bullets under a new version heading with the date, tags `v<x.y.z>` and cuts a `gh release` whose notes are that section. Dates belong in this file and nowhere else — the no-dates rule holds everywhere but here, because Keep a Changelog asks for them
