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
          name
          font
          screenShader
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
        follower; the full-screen flash also needs `screenShader`, and degrades to
        text-only garbling without it
      '';
    };

    screenShader = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression "config.programs.screen-shader.package";
      description = ''
        The [screen-shader](https://github.com/rokokol/hyprland-screen-shader) command that
        flashes the whole screen on a glitch. Without it the glitch is text-only
      '';
    };

    name = lib.mkOption {
      type = lib.types.str;
      default = "Monika";
      description = "The name on the plate; it glitches with the text";
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
        What she talks about: blocks separated by a blank line, `#` lines are comments and
        `[player]` becomes the user's name. Defaults to the shipped in-game dialogue
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
