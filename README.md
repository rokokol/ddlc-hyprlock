<div align="center">

# ddlc-hyprlock

**The Doki Doki Literature Club lock screen: Act 3** (｡•̀ᴗ-)✧

![hyprlock](https://img.shields.io/badge/hyprlock-lock_screen-58E1FF?style=flat)
![Nix](https://img.shields.io/badge/Nix-flake-7EBAE4?style=flat&logo=nixos&logoColor=white)
[![palette](https://img.shields.io/badge/colours-ddlc--palette-FF80C0?style=flat)](https://github.com/rokokol/ddlc-palette)
[![assets](https://img.shields.io/badge/assets-Team_Salvato-FF80C0?style=flat)](ASSETS.md)
[![license](https://img.shields.io/badge/MIT-3DA639?style=flat)](LICENSE)
[![build](https://github.com/rokokol/ddlc-hyprlock/actions/workflows/build.yml/badge.svg)](https://github.com/rokokol/ddlc-hyprlock/actions/workflows/build.yml)

</div>

Every colour is a measured one out of [ddlc-palette](https://github.com/rokokol/ddlc-palette), which reads them off [ddlc.moe](https://ddlc.moe) — nothing here is eyeballed

> [!NOTE]
> Unaffiliated with and not endorsed by Team Salvato. The dialog box, the background and every line she says are theirs — see [ASSETS.md](ASSETS.md)

Came over from my rice, **[rokokol/huix](https://github.com/rokokol/huix)**

```sh
# render the config and read it, installing nothing
nix build github:rokokol/ddlc-hyprlock && cat result/share/ddlc-hyprlock/hyprlock.conf
```

## Contents

- [UI](#ui)
  - [What it looks like](#what-it-looks-like)
  - [How the dialog works](#how-the-dialog-works)
  - [Glitches](#glitches)
  - [Her own words](#her-own-words)
- [Install](#install)
  - [Home Manager](#home-manager)
  - [Any other distribution](#any-other-distribution)
  - [The font is not in here](#the-font-is-not-in-here)
- [Running a lock](#running-a-lock)
- [Tests](#tests)
- [Layout](#layout)
- [License](#license)

## UI

### What it looks like

![The lock screen: the clock over the classroom, Monika behind it, her dialog box along the bottom](docs/lock-screen.jpg)

The line types out a character at a time, wraps inside the box when it is too long, and garbles when a glitch fires — all three in nine seconds:

![The dialog box typing a line, wrapping the next one and garbling in between](docs/dialog.gif)

*[the full recording](docs/demo.mp4)*

A wrong password is a glitch with a reason: the plate and the line break up, and the field says as much

![A wrong password: the name and the line garbled, the field reading "This isn't it... (1)"](docs/glitch.jpg)

> The date is `date +"%A, %B %-d"`, so it comes out in whatever locale the session runs in — Russian in these shots

### How the dialog works

The box is a static image and the text is two labels on top of it. The engine renders a frame and writes it into `stateDir` — `frame` for the line, `name` for the plate — and the labels in the config are `cmd[update:100] cat` on exactly those two files, so hyprlock picks the frame up on its own poll. It is a rewrite each way rather than a signal because hyprlock's `SIGUSR2` handler walks its timer vector without the mutex and allocates inside the handler, so pushing into a busy locker wedges it ([hyprwm/hyprlock#539](https://github.com/hyprwm/hyprlock/pull/539))

Typing is the Ren'Py trick: every frame renders the *whole* line and hides the part not yet typed in a transparent span. That is only half of standing still, though — a hyprlock label has no width and no corner to anchor to, it is placed by its own texture. So the frame is padded on every side that could move: blank lines up to the height of the text area, and a closing line of spaces wider than any line will be. With the texture size constant, `halign = center` plus `valign = bottom` pin the top-left corner of the text at the box's padding, and the line grows to the right instead of creeping out from the middle. All of it needs `text_trim = false`, which is why the config sets it

Geometry is computed in [`nix/config.nix`](nix/config.nix) from the dialog box's own 1280x720 canvas, and the width it gives the text area is handed to the engine — the wrap has to be the same number the labels were laid out at. A replacement `dialogImage` has to keep that canvas

### Glitches

One mechanism for two triggers: a wrong password, and a Poisson stream of spontaneous firings. Both garble the name and the text with mojibake, and both flash the whole screen — for a shorter time than the text stays broken. A wrong password arrives as a line from a `journalctl -f` follower, which is also what the loop sleeps on: no polling of the journal, and the reaction is immediate. `glitch = false` drops the follower and the stream both — the dialog still types, it just never garbles

The flash is the compositor's job, not hyprlock's, and `flash` picks who does it:

| `flash`         | what it does                                                                                                                                                    | what to know                                                                                                                                                |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `hyprctl`       | sets the shipped [`shaders/glitch.frag`](shaders/glitch.frag) in `decoration:screen_shader`, and empties that option when the flash is over                     | needs nothing but Hyprland. It empties the option rather than putting back what was in it, so a screen shader of your own does not survive the first glitch |
| `screen-shader` | hands the flash to [screen-shader](https://github.com/rokokol/hyprland-screen-shader), which composites it over the effect already on screen and puts that back | set `screenShader` to the package, which selects this mode by itself                                                                                        |
| `none`          | nothing, the glitch stays text-only                                                                                                                             |                                                                                                                                                             |

Either way the clearing is on the engine's own clock, in the same loop that renders frames — no background sleeper that could outlive the lock, and a lock killed mid-flash still takes the shader down with it

### Her own words

`quotesFile` and `reentryFile` are plain text: blocks separated by a blank line, one line of dialogue per line, `#` for comments. A lock opens with a block from `reentryFile` — she notices you came back — and then draws from `quotesFile`, never the same block twice in a row. What is shipped is her Act 3 dialogue, verbatim

Two things in a line are substituted, both of them things she says about the machine she is on:

- `[player]` — `$USER`, the name she calls you by
- `[chr]` — `characterDir`, the folder she names when she talks about where her character file is kept, the way the game names the one called `characters`. It follows the directory `quotesFile` is in: on this machine that folder is the one that actually holds her, so the backup she asks for is one you could make

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

| option            | what it does                                                                                                                                             | default                                                    |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| `dialog`          | the box, the typed quotes and the name plate. Off leaves the background, clock, date, layout and input field                                             | `true`                                                     |
| `glitch`          | garble the dialog on a wrong password and at random intervals                                                                                            | follows `dialog`                                           |
| `flash`           | how the whole screen flashes on a glitch: `hyprctl`, `screen-shader` or `none`                                                                           | `screen-shader` when `screenShader` is set, else `hyprctl` |
| `screenShader`    | the [screen-shader](https://github.com/rokokol/hyprland-screen-shader) package, for that mode                                                            | `null`                                                     |
| `glitchShader`    | the shader `hyprctl` mode sets — a complete Hyprland screen shader, not an effect body                                                                   | [`shaders/glitch.frag`](shaders/glitch.frag)               |
| `name`            | the name on the plate                                                                                                                                    | `Monika`                                                   |
| `characterDir`    | what `[chr]` in a line becomes                                                                                                                           | the directory `quotesFile` is in                           |
| `font`            | the font every label and the input field are set in                                                                                                      | `Doki`                                                     |
| `background`      | the wallpaper behind the lock                                                                                                                            | `assets/just-monika.png`                                   |
| `dialogImage`     | the dialog box the text sits in                                                                                                                          | `assets/dialog-box.png`                                    |
| `quotesFile`      | what she talks about                                                                                                                                     | `assets/monika-talk.txt`, her Act 3 dialogue               |
| `reentryFile`     | the topics a lock opens with                                                                                                                             | `assets/monika-reentry.txt`                                |
| `placeholderText` | what the empty password field says                                                                                                                       | `<i>Give me it...~</i>`                                    |
| `failText`        | what a wrong password says                                                                                                                               | `This isn't it... ($ATTEMPTS)`                             |
| `stateDir`        | the directory the rendered frame is handed over in: the engine writes `frame` and `name` there, the labels `cat` them                                    | `${XDG_RUNTIME_DIR:-/tmp}/hypr-ddlc`                       |
| `pollMs`          | how often hyprlock re-reads that frame, ms. Also the engine's frame rate and one character of typing, and every tick costs a shell — a floor, not a knob | `100`                                                      |
| `lockCommand`     | read-only, and the one thing you have to consume: the exact command that takes a lock                                                                    | the engine, or plain hyprlock without `dialog`             |

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

The engine finds the assets, the quotes and the shader from its own location, so nothing has to be set. Everything it does read is documented in `ddlc-hyprlock help`

> [!NOTE]
> bash 5.2 or newer. The frame is rendered in pure bash — no fork per character — and both `EPOCHREALTIME` and the pango escaping depend on that version

### The font is not in here

The config asks for **Doki**, the game's own face, which is not shipped — a theme has no business installing fonts, and that one is copyrighted besides. Set `font` to whatever you have, or install Doki yourself and leave it alone. The geometry does not depend on it: the text is pinned by texture size, not by font metrics

## Running a lock

`ddlc-hyprlock lock` starts hyprlock as its own child and animates the dialog until the locker exits. It never kills hyprlock, so the engine dying cannot unlock the screen, and it blocks for exactly as long as the lock — which is what an idle daemon wants from a lock command. `lockCommand` is that command, spelled out for whoever needs it:

```nix
services.hypridle.settings.general.lock_cmd = "pidof hyprlock || ${config.ddlc.hyprlock.lockCommand}";
```

It is read-only because it is derived, not chosen: with `dialog` off it is plain hyprlock and there is no engine to run, so setting it by hand could only disagree with what is installed

A keybind should not call it directly — go through the session, so that everything that locks the screen takes the same path:

```conf
bind = SUPER, F12, exec, loginctl lock-session
```

## Tests

```sh
tests/run.sh            # the engine, against a stub locker, journal, hyprctl and screen-shader
tests/run.sh --update   # rewrite the goldens
```

The suite drives the packaged command rather than the script, since the wrapper's defaults are half of what there is to get wrong, and it isolates `HOME`, `XDG_RUNTIME_DIR` and `XDG_DATA_HOME` — a session exports the last two, and the engine would otherwise publish frames into the live lock's state directory. It also refuses to run unless every stub is executable and first on `PATH`: a stub that is neither hands the test the real tool, and for `hyprctl` that means a live compositor instead of a log file

`nix flake check` runs that plus: `dist/` is what the package would render, the packaged config has no placeholder left in it and reads the state files, and the Home Manager module is evaluated against option stubs — with the dialog on and off, because a plain lock has to be genuinely plain, and with a flash that has no compositor or no package behind it, because that is a warning and an error respectively

## Layout

```
nix/config.nix       the whole lock screen as data: geometry, colours, labels
nix/render.nix       that attrset -> hyprlock.conf, for the consumers Home Manager cannot serve
nix/                 package.nix, module.nix, module-test.nix
ddlc-hyprlock.sh     the dialog engine
assets/              the background, the dialog box, and what she says
shaders/glitch.frag  the flash, for the mode that needs no dependency
dist/                the rendered config, committed for consumers without Nix
docs/                the screenshots and the recording the README shows
tests/run.sh         the engine's suite, with stubs and goldens
install.sh           for systems without Nix
```

## License

Doki Doki Literature Club is by [Team Salvato](https://teamsalvato.com/). This is non-commercial fan content, and what every bundled file is comes from [ASSETS.md](ASSETS.md). The code is MIT
