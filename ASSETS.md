# Assets and third-party content

`LICENSE` (MIT) covers the **code** in this repository — the Nix expressions and the shell. It does **not** cover the artwork and the text under `assets/`, which belong to their owner and are included as fan content

## Doki Doki Literature Club

Doki Doki Literature Club and Doki Doki Literature Club Plus are the property of [Team Salvato](https://teamsalvato.com/). This project is **unaffiliated with and not endorsed by Team Salvato**

The following are derived from or contain official DDLC assets:

| Path | What |
| --- | --- |
| `assets/dialog-box.png` | the in-game dialog box, drawn on the lock screen |
| `assets/just-monika.png` | the background |
| `assets/monika-talk.txt`, `assets/monika-reentry.txt` | **the game's script**: Monika's Act 3 dialogue and her lines on re-entering the game, transcribed line for line. Nothing here is written in her voice — every line is hers as shipped, with `[player]` left where the game puts the player's name. One line departs from the transcription: where she says her character file is "in the folder called characters", the placeholder `[chr]` takes the phrase's place, so she names a path on the machine she is actually running on |

The `Doki` font family the config asks for is Team Salvato's and is **not** shipped here. Without it hyprlock falls back to whatever fontconfig resolves; see the README for how to point the config at another font

`shaders/glitch.frag` is not a game asset — it is a GLSL effect of my own, MIT like the rest of the code, and the same one [rokokol/hyprland-screen-shader](https://github.com/rokokol/hyprland-screen-shader) ships as a composable body

The colours are measured off [ddlc.moe](https://ddlc.moe) by [ddlc-palette](https://github.com/rokokol/ddlc-palette) and are theirs too

Use here follows [Team Salvato's IP guidelines](https://teamsalvato.com/ip-guidelines): this is non-commercial fan content, nothing containing official assets is sold, and no claim of affiliation is made. If you reuse any of it, the same conditions apply to you

Team Salvato reserves the right to act on copyright or trademark infringement; nothing here grants a licence to their intellectual property
