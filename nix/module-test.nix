# Evaluates the Home Manager module against stubs for the option paths it writes to, so the
# wiring is checked without pulling home-manager in as an input. Produces the values it would
# emit; flake.nix turns them into assertions
{
  lib,
  pkgs,
  module,
}:

let
  stubs =
    { lib, ... }:
    {
      options = {
        home.packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
        };
        assertions = lib.mkOption {
          type = lib.types.listOf lib.types.unspecified;
          default = [ ];
        };
        warnings = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        # The flash needs a compositor, so the module reads whether there is one
        wayland.windowManager.hyprland.enable = lib.mkEnableOption "hyprland";
        programs.hyprlock.enable = lib.mkEnableOption "hyprlock";
        programs.hyprlock.package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.hyprlock;
        };
        programs.hyprlock.settings = lib.mkOption {
          type = lib.types.attrsOf lib.types.unspecified;
          default = { };
        };
      };
    };

  eval =
    user:
    (lib.evalModules {
      modules = [
        stubs
        module
        user
      ];
      specialArgs = { inherit pkgs; };
    }).config;

  on = eval {
    ddlc.hyprlock.enable = true;
    wayland.windowManager.hyprland.enable = true;
  };
  # A flash without a compositor to paint it is a warning, not an error
  noCompositor = eval { ddlc.hyprlock.enable = true; };
  # Handing the flash to screen-shader without handing over the package is an error
  shaderless = eval {
    ddlc.hyprlock = {
      enable = true;
      flash = "screen-shader";
    };
    wayland.windowManager.hyprland.enable = true;
  };
  withShader = eval {
    ddlc.hyprlock = {
      enable = true;
      screenShader = pkgs.hello;
    };
    wayland.windowManager.hyprland.enable = true;
  };
  plain = eval {
    ddlc.hyprlock = {
      enable = true;
      dialog = false;
    };
  };
  tuned = eval {
    ddlc.hyprlock = {
      enable = true;
      name = "Sayori";
    };
  };
  off = eval { ddlc.hyprlock.enable = false; };

  # The dialog is two labels on top of the three the plain lock has
  labels = c: builtins.length c.programs.hyprlock.settings.label;
  images = c: builtins.length (c.programs.hyprlock.settings.image or [ ]);
  texts = c: map (l: l.text) c.programs.hyprlock.settings.label;
in
{
  # Joined rather than indexed, so "installed nothing" fails the assertion instead of
  # blowing up during evaluation with an unhelpful list error
  package = lib.concatMapStringsSep " " toString on.home.packages;
  # The name is baked into the wrapper, so changing it has to move the store path
  tunedPackage = lib.concatMapStringsSep " " toString tuned.home.packages;

  hyprlockEnabled = on.programs.hyprlock.enable;

  labels = labels on;
  images = images on;
  texts = texts on;
  # The background has to come out of the package, or the lock shows a colour and no image
  background = (builtins.head on.programs.hyprlock.settings.background).path;
  font = (builtins.head on.programs.hyprlock.settings.label).font_family;

  lockCommand = on.ddlc.hyprlock.lockCommand;

  # Nothing to install and nothing to say when the flash needs no help
  flash = on.ddlc.hyprlock.flash;
  warnings = on.warnings;
  failedAssertions = map (a: a.message) (builtins.filter (a: !a.assertion) on.assertions);
  # Setting the package is what selects that mode, so it is not said twice
  shaderFlash = withShader.ddlc.hyprlock.flash;
  noCompositorWarnings = builtins.length noCompositor.warnings;
  shaderlessAssertions = builtins.length (builtins.filter (a: !a.assertion) shaderless.assertions);

  # Without the dialog nothing polls a state directory and nothing needs the engine
  plainLabels = labels plain;
  plainImages = images plain;
  plainTexts = texts plain;
  plainLockCommand = plain.ddlc.hyprlock.lockCommand;
  plainPackages = plain.home.packages;

  offPackages = off.home.packages;
  offHyprlock = off.programs.hyprlock.enable;
  offSettings = lib.attrNames off.programs.hyprlock.settings;
}
