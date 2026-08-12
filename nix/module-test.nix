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

  on = eval { ddlc.hyprlock.enable = true; };
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
