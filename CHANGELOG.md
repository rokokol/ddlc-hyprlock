# Changelog

Kept in the shape of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioned by [semver](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

## [1.0.0] - 2026-08-13

Split out of [rokokol/huix](https://github.com/rokokol/huix), where the config and the dialog engine sat in the Hyprland directory

### Added

- the lock screen: the clock over the classroom, Monika behind it, her Act 3 dialog along the bottom
- the engine: typing, wrapping, glitches on a wrong password and on a Poisson stream, the flash through `hyprctl` or `screen-shader`
- `nix/config.nix` as data and `nix/render.nix` as the renderer, so the config reaches both Home Manager and a `dist/` install without Nix
- `homeModules.default` (`ddlc.hyprlock`), which also exports `lockCommand`, and `overlays.default`
- checks: the engine against a stub locker with goldens, `dist/` current, the packaged config free of placeholders, module wiring with the dialog on and off
- a weekly `palette-drift.yml` that re-renders against the palette's HEAD rather than the lock
