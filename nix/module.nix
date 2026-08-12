# Home Manager module. It writes the hyprlock config and installs the dialog engine, but it
# does not start anything: what runs a lock is `lockCommand`, which the idle daemon (or a
# keybind) has to be pointed at — the engine must be the parent of hyprlock, not a daemon
# beside it, so that a lock lasts exactly as long as the command
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.ddlc.hyprlock;
  share = "${cfg.package}/share/ddlc-hyprlock";

  # The same rule the package follows: an unset path means the shipped asset
  pick = given: shipped: if given != null then toString given else "${share}/${shipped}";
in
{
  options.ddlc.hyprlock = {
    enable = lib.mkEnableOption "the DDLC lock screen for hyprlock";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.ddlc-hyprlock.override {
        inherit (cfg)
          glitch
          flash
          name
          characterFile
          font
          screenShader
          glitchShader
          stateDir
          pollMs
          placeholderText
          failText
          background
          dialogImage
          ;
        withDialog = cfg.dialog;
        quotes = cfg.quotesFile;
        reentry = cfg.reentryFile;
        # The locker the engine starts is the one this Home Manager installs
        hyprlock = config.programs.hyprlock.package;
      };
      defaultText = lib.literalExpression "ddlc-hyprlock carrying the settings below";
      description = "The package to install; it carries the dialog engine and its settings";
    };

    dialog = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Monika's dialog box: the box image, the typed quotes and the name plate. Costs two
        labels polled at `pollMs`, each spawning a shell, plus the engine's own loop.
        Off leaves the background, clock, date, layout and input field
      '';
    };

    glitch = lib.mkOption {
      type = lib.types.bool;
      default = cfg.dialog;
      defaultText = lib.literalExpression "config.ddlc.hyprlock.dialog";
      description = ''
        Garble the dialog on a wrong password and at random intervals. Adds a journal
        follower; whether the whole screen flashes along with the text is `flash`
      '';
    };

    flash = lib.mkOption {
      type = lib.types.enum [
        "hyprctl"
        "screen-shader"
        "none"
      ];
      default = if cfg.screenShader != null then "screen-shader" else "hyprctl";
      defaultText = lib.literalExpression ''"screen-shader" when screenShader is set, else "hyprctl"'';
      description = ''
        How the whole screen flashes on a glitch — the text garbles either way:

        - `hyprctl` sets `glitchShader` and clears the option again when the flash is over.
          It needs nothing but Hyprland, and it **owns** `decoration:screen_shader` while it
          runs: anything else you had in there is gone after the first glitch
        - `screen-shader` hands the flash to
          [screen-shader](https://github.com/rokokol/hyprland-screen-shader), which composites
          it over the effect already on screen and puts that back afterwards. Set
          `screenShader` to its package
        - `none` leaves the glitch text-only
      '';
    };

    screenShader = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression "config.programs.screen-shader.package";
      description = ''
        The [screen-shader](https://github.com/rokokol/hyprland-screen-shader) package, for
        `flash = "screen-shader"` — which is what setting this selects by default
      '';
    };

    glitchShader = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        The shader `flash = "hyprctl"` sets, a complete Hyprland screen shader rather than an
        effect body. Defaults to the shipped one
      '';
    };

    name = lib.mkOption {
      type = lib.types.str;
      default = "Monika";
      description = "The name on the plate; it glitches with the text";
    };

    characterFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "$HOME/ddlc/game/characters/monika.chr";
      description = ''
        What `[chr]` in a line becomes — the path she names when she talks about her own
        character file. Defaults to `quotesFile`, which on this machine is where she does in
        fact live, so the path she names is one you could actually back up
      '';
    };

    font = lib.mkOption {
      type = lib.types.str;
      default = "Doki";
      example = "Sans";
      description = ''
        The font every label and the input field are set in. `Doki` is the game's own font,
        which this package does not ship — install it yourself or name another one
      '';
    };

    background = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "The wallpaper behind the lock. Defaults to the shipped one";
    };

    dialogImage = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        The dialog box the text sits in. The geometry is measured off the shipped 1280x720
        asset, so a replacement has to keep its canvas
      '';
    };

    quotesFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        What she talks about: blocks separated by a blank line, `#` lines are comments,
        `[player]` becomes the user's name and `[chr]` becomes `characterFile`. Defaults to
        the shipped Act 3 dialogue, which uses `[player]` and no `[chr]`
      '';
    };

    reentryFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "The topics a lock opens with. Same format as `quotesFile`";
    };

    placeholderText = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "<i>Give me it...~</i>";
      description = "What the empty password field says; pango markup is allowed";
    };

    failText = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "This isn't it... ($ATTEMPTS)";
      description = "What a wrong password says";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "\${XDG_RUNTIME_DIR:-/tmp}/hypr-ddlc";
      description = ''
        Where the engine publishes the rendered frame the labels read. Left unexpanded on
        purpose: the labels are run through a shell, so this is resolved per session
      '';
    };

    pollMs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 100;
      description = ''
        How often hyprlock re-reads the frame, ms. This is also the engine's frame rate and
        one character of typing, and every tick costs a shell — so it is a floor, not a knob
      '';
    };

    lockCommand = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default =
        if cfg.dialog then
          "${lib.getExe cfg.package} lock"
        else
          lib.getExe config.programs.hyprlock.package;
      defaultText = lib.literalExpression "the engine when `dialog` is on, plain hyprlock otherwise";
      description = ''
        What runs a lock — point hypridle's `lock_cmd` (or a keybind) at it. It blocks for
        the whole lock and never kills the locker, so dying cannot unlock the screen
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.flash != "screen-shader" || cfg.screenShader != null;
        message = ''
          ddlc.hyprlock.flash = "screen-shader" needs ddlc.hyprlock.screenShader set to that
          package — the engine cannot guess a command it does not ship. Use flash = "hyprctl"
          for a flash with no dependency
        '';
      }
    ];

    # Either flash paints the whole screen, which only a compositor can do — hyprlock draws
    # its own surface and nothing else. Said as a warning, not an assertion: a lock screen on
    # a Hyprland this configuration does not itself enable is a legitimate setup
    warnings =
      lib.optional
        (cfg.dialog && cfg.glitch && cfg.flash != "none" && !config.wayland.windowManager.hyprland.enable)
        "ddlc.hyprlock.flash = \"${cfg.flash}\" flashes the whole screen through Hyprland, which this configuration does not enable. Without it the glitch stays text-only";

    # Only the dialog needs the engine on PATH; the theme alone is just a config file
    home.packages = lib.optional cfg.dialog cfg.package;

    programs.hyprlock = {
      enable = true;

      settings =
        (import ./config.nix (
          {
            palette = self.lib.palette;
            inherit (cfg)
              dialog
              font
              stateDir
              pollMs
              ;
            background = pick cfg.background "just-monika.png";
            dialogImage = pick cfg.dialogImage "dialog-box.png";
          }
          // lib.filterAttrs (_: v: v != null) { inherit (cfg) placeholderText failText; }
        )).settings;
    };
  };
}
