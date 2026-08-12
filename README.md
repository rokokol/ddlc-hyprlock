<div align="center">

# ddlc-hyprlock

**The Doki Doki Literature Club lock screen, with Monika typing while you are away** (｡•̀ᴗ-)✧

![hyprlock](https://img.shields.io/badge/hyprlock-lock_screen-58E1FF?style=flat)
![Nix](https://img.shields.io/badge/Nix-flake-7EBAE4?style=flat&logo=nixos&logoColor=white)
[![palette](https://img.shields.io/badge/colours-ddlc--palette-FF80C0?style=flat)](https://github.com/rokokol/ddlc-palette)
[![assets](https://img.shields.io/badge/assets-Team_Salvato-FF80C0?style=flat)](ASSETS.md)
[![license](https://img.shields.io/badge/MIT-3DA639?style=flat)](LICENSE)
[![build](https://github.com/rokokol/ddlc-hyprlock/actions/workflows/build.yml/badge.svg)](https://github.com/rokokol/ddlc-hyprlock/actions/workflows/build.yml)

[Русский](README.ru.md)

</div>

A hyprlock theme plus the dialog it needs to be alive: the game's dialog box sits at the bottom of the lock screen and Monika types into it, one character at a time, from the same lines she says in the game. A wrong password garbles the text and glitches the screen

> [!NOTE]
> Unaffiliated with and not endorsed by Team Salvato. The dialog box, the background and every line she says are theirs — see [ASSETS.md](ASSETS.md)

Every colour is a measured one out of [ddlc-palette](https://github.com/rokokol/ddlc-palette), which reads them off [ddlc.moe](https://ddlc.moe) — nothing here is eyeballed

Came over from my rice, **[rokokol/huix](https://github.com/rokokol/huix)**

```sh
# render the config and read it, installing nothing
nix build github:rokokol/ddlc-hyprlock && cat result/share/ddlc-hyprlock/hyprlock.conf
```

## Contents

- [Install](#install)
  - [Home Manager](#home-manager)
  - [Any other distribution](#any-other-distribution)
  - [The font is not in here](#the-font-is-not-in-here)
- [Running a lock](#running-a-lock)
- [How the dialog works](#how-the-dialog-works)
- [Glitches](#glitches)
- [Her own words](#her-own-words)
- [Tests](#tests)
- [Layout](#layout)
- [License](#license)

## Install

### Home Manager

```nix
{
  inputs.ddlc-hyprlock.url = "github:rokokol/ddlc-hyprlock";

  # in your home configuration
  imports = [ inputs.ddlc-hyprlock.homeManagerModules.default ];

  ddlc.hyprlock.enable = true;
}
```

That enables `programs.hyprlock`, writes the whole config, and installs the dialog engine. It starts nothing — see [running a lock](#running-a-lock)

| option | | default |
| --- | --- | --- |
| `dialog` | the box, the typed quotes and the name plate. Off leaves the background, clock, date, layout and input field | `true` |
| `glitch` | garble the dialog on a wrong password and at random intervals | follows `dialog` |
| `screenShader` | the [screen-shader](https://github.com/rokokol/hyprland-screen-shader) package that flashes the whole screen on a glitch | `null` |
| `name` | the name on the plate | `Monika` |
| `font` | the font every label and the input field are set in | `Doki` |
| `background` | the wallpaper behind the lock | the shipped one |
| `dialogImage` | the dialog box the text sits in | the shipped one |
| `quotesFile` | what she talks about | the shipped in-game dialogue |
| `reentryFile` | the topics a lock opens with | the shipped ones |
| `placeholderText` | what the empty password field says | `<i>Give me it...~</i>` |
| `failText` | what a wrong password says | `This isn't it... ($ATTEMPTS)` |
| `stateDir` | where the engine publishes the frame the labels read | `${XDG_RUNTIME_DIR:-/tmp}/hypr-ddlc` |
| `pollMs` | how often hyprlock re-reads that frame, ms | `100` |
| `lockCommand` | read-only: what runs a lock | the engine, or plain hyprlock without `dialog` |

### Any other distribution

```sh
git clone https://github.com/rokokol/ddlc-hyprlock
cd ddlc-hyprlock
sudo ./install.sh          # PREFIX=~/.local ./install.sh for a user install
```

Nothing is built: [`dist/`](dist) is the rendered config, committed, and `install.sh` only substitutes where the assets landed. Then take it and run a lock through the engine:

```sh
cp /usr/local/share/ddlc-hyprlock/hyprlock.conf ~/.config/hypr/hyprlock.conf
ddlc-hyprlock lock
```

The engine finds the assets and the quotes from its own location, so nothing has to be set. Everything it does read is [documented](#layout) in `ddlc-hyprlock help`

> [!NOTE]
> bash 5.2 or newer. The frame is rendered in pure bash — no fork per character — and both `EPOCHREALTIME` and the pango escaping depend on that version

### The font is not in here

The config asks for **Doki**, the game's own face, which is not shipped — a theme has no business installing fonts, and that one is copyrighted besides. Set `font` to whatever you have, or install Doki yourself and leave it alone. The geometry does not depend on it: the text is pinned by texture size, not by font metrics

## Running a lock

`ddlc-hyprlock lock` starts hyprlock as its own child and animates the dialog until the locker exits. It never kills hyprlock, so the engine dying cannot unlock the screen, and it blocks for exactly as long as the lock — which is what an idle daemon wants from a lock command:

```nix
services.hypridle.settings.general.lock_cmd = "pidof hyprlock || ${config.ddlc.hyprlock.lockCommand}";
```

A keybind should not call it directly — go through the session, so that everything that locks the screen takes the same path:

```conf
bind = SUPER, F12, exec, loginctl lock-session
```

## How the dialog works

The box is a static image and the text is two labels on top of it. The engine publishes the rendered line and the name into `stateDir`, and the labels just `cat` those files on hyprlock's own poll — a rewrite each way instead of a signal, because hyprlock's `SIGUSR2` handler walks its timer vector without the mutex and allocates inside the handler, so pushing into a busy locker wedges it ([hyprwm/hyprlock#539](https://github.com/hyprwm/hyprlock/pull/539))

Typing is the Ren'Py trick: every frame renders the *whole* line and hides the part not yet typed in a transparent span, so the texture keeps its size for the life of the line and the text never shifts under itself. Padding with blank lines and a trailing line of spaces keeps the box constant in both directions, which is why the config sets `text_trim = false`

Geometry is computed in [`nix/config.nix`](nix/config.nix) from the dialog box's own 1280x720 canvas, and the width it gives the text area is handed to the engine — the wrap has to be the same number the labels were laid out at. A replacement `dialogImage` has to keep that canvas

## Glitches

One mechanism for two triggers: a wrong password, and a Poisson stream of spontaneous firings. Both garble the name and the text with mojibake and, if `screenShader` is set, flash the whole screen through [screen-shader](https://github.com/rokokol/hyprland-screen-shader) — composited over whatever effect is already on. Without it the glitch is text-only, which is a degradation, not an error

A wrong password arrives as a line from a `journalctl -f` follower, which is also what the loop sleeps on: no polling of the journal, and the reaction is immediate. `glitch = false` drops the follower and the stream both — the dialog still types, it just never garbles

## Her own words

`quotesFile` and `reentryFile` are plain text: blocks separated by a blank line, one line of dialogue per line, `#` for comments, `[player]` for the user's name. A lock opens with a block from `reentryFile` — she notices you came back — and then draws from `quotesFile`, never the same block twice in a row

## Tests

```sh
tests/run.sh            # the engine, against a stub locker and a stub journal
tests/run.sh --update   # rewrite the goldens
```

The suite drives the packaged command rather than the script, since the wrapper's defaults are half of what there is to get wrong, and it isolates both `HOME` and `XDG_RUNTIME_DIR` — a session exports the second one, and the engine would otherwise publish into the live lock's state directory

`nix flake check` runs that plus: `dist/` is what the package would render, the packaged config has no placeholder left in it and reads the state files, and the Home Manager module is evaluated against option stubs — with the dialog on and off, because a plain lock has to be genuinely plain

## Layout

```
nix/config.nix       the whole lock screen as data: geometry, colours, labels
nix/render.nix       that attrset -> hyprlock.conf, for the consumers Home Manager cannot serve
nix/                 package.nix, module.nix, module-test.nix
ddlc-hyprlock.sh     the dialog engine
assets/              the background, the dialog box, and what she says
dist/                the rendered config, committed for consumers without Nix
tests/run.sh         the engine's suite, with stubs and goldens
install.sh           for systems without Nix
```

## License

Doki Doki Literature Club is by [Team Salvato](https://teamsalvato.com/). This is non-commercial fan content, and what every bundled file is comes from [ASSETS.md](ASSETS.md). The code is MIT
