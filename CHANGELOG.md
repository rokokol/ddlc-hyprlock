# Changelog

Kept in the shape of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioned by [semver](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

## [1.0.1] - 2026-08-14

### Added

- `shaders-compile` check: every shader is compiled by glslang in `nix flake check`, because Hyprland announces one it refuses on its on-screen error bar and in no log a script can read. It counts the shaders first — `nullglob` is on in a builder, so an empty glob would pass a loop that never ran
- `tests/live.sh` runs the flash against the real compositor and checks that `debug:damage_tracking` and `debug:vfr` come back at the values the session had

### Fixed

- `glitch.frag` starts with `#version`, which an ES shader is only valid with — Hyprland tolerated the comment above it, standard GLSL does not

### Changed

- the `hyprctl` and `screen-shader` stubs separate their logged arguments with a pipe, so a `--batch` split across several arguments no longer reads like one
- the suite prints which engine it is driving: the default is whatever `ddlc-hyprlock` PATH resolves to, and on a developer's machine that is the installed package rather than the checkout

## [1.0.0] - 2026-08-13

Split out of [rokokol/huix](https://github.com/rokokol/huix), where the config and the dialog engine sat in the Hyprland directory

### Added

- the lock screen: the clock over the classroom, Monika behind it, her Act 3 dialog along the bottom
- the engine: typing, wrapping, glitches on a wrong password and on a Poisson stream, the flash through `hyprctl` or `screen-shader`
- `nix/config.nix` as data and `nix/render.nix` as the renderer, so the config reaches both Home Manager and a `dist/` install without Nix
- `homeModules.default` (`ddlc.hyprlock`), which also exports `lockCommand`, and `overlays.default`
- checks: the engine against a stub locker with goldens, `dist/` current, the packaged config free of placeholders, module wiring with the dialog on and off
- a weekly `palette-drift.yml` that re-renders against the palette's HEAD rather than the lock
