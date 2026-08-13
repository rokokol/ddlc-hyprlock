{
  description = "The Doki Doki Literature Club lock screen for hyprlock, with Monika's dialog";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ddlc-palette = {
      url = "github:rokokol/ddlc-palette";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      ddlc-palette,
    }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Each piece isolated, so a README edit does not rebuild anything
      engine = builtins.path {
        name = "ddlc-hyprlock.sh";
        path = ./ddlc-hyprlock.sh;
      };
      testsDir = builtins.path {
        name = "ddlc-hyprlock-tests";
        path = ./tests;
      };
      distDir = builtins.path {
        name = "ddlc-hyprlock-dist";
        path = ./dist;
      };
      installer = builtins.path {
        name = "install.sh";
        path = ./install.sh;
      };

      render = import ./nix/render.nix { inherit lib; };

      # The conf as it is committed and as install.sh consumes it: asset paths still a
      # placeholder, because a copy outside the store cannot know where it will land
      template = import ./nix/config.nix {
        palette = self.lib.palette;
        background = "@share@/just-monika.png";
        dialogImage = "@share@/dialog-box.png";
      };
    in
    {
      packages = forAllSystems (pkgs: rec {
        default = ddlc-hyprlock;
        ddlc-hyprlock = pkgs.callPackage ./nix/package.nix {
          palette = self.lib.palette;
          inherit (pkgs) hyprlock;
        };

        # What dist/ is regenerated from — the palette-drift workflow builds this and copies it in
        dist = pkgs.runCommand "ddlc-hyprlock-dist" { } ''
          mkdir -p $out
          cp ${pkgs.writeText "hyprlock.conf.in" (render template.settings)} $out/hyprlock.conf.in
        '';
      });

      # homeModules is the name the flake schema knows; homeManagerModules is what most
      # consumers still write, so both point at the same module
      homeModules.default = import ./nix/module.nix { inherit self; };
      homeManagerModules.default = self.homeModules.default;

      lib = {
        # The lock screen as plain data, for a consumer that wants to render it itself
        config = import ./nix/config.nix;
        inherit render;
        # Bare hex, without the "#" — the spelling hyprlock reads
        palette = ddlc-palette.lib.bare;
      };

      # For a consumer who reaches for pkgs rather than this flake's packages directly
      overlays.default = final: _prev: {
        inherit (self.packages.${final.stdenv.hostPlatform.system}) ddlc-hyprlock;
      };

      checks = forAllSystems (
        pkgs:
        let
          ddlc-hyprlock = self.packages.${pkgs.stdenv.hostPlatform.system}.ddlc-hyprlock;
        in
        {
          # The engine's own suite, run against the packaged command rather than the script:
          # the wrapper's defaults are half of what there is to get wrong
          tests =
            pkgs.runCommand "tests"
              {
                nativeBuildInputs = with pkgs; [
                  bash
                  coreutils
                  gawk
                  gnugrep
                  diffutils
                  ddlc-hyprlock
                ];
              }
              ''
                cp -r ${testsDir}/. tests
                chmod -R +w tests
                patchShebangs tests
                bash tests/run.sh
                touch $out
              '';

          # dist/ is committed so a consumer without Nix just copies a file; this proves it is
          # what the package would have written
          dist-is-current = pkgs.runCommand "dist-is-current" { } ''
            diff -r ${distDir} ${self.packages.${pkgs.stdenv.hostPlatform.system}.dist}
            touch $out
          '';

          # hyprlock has no way to check a config without a session, so the shape is the check:
          # the substitution has to have happened, and the dialog has to read the state files
          conf-shape = pkgs.runCommand "conf-shape" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
            conf=${ddlc-hyprlock}/share/ddlc-hyprlock/hyprlock.conf

            if grep -q '@share@' "$conf"; then
              echo "the asset placeholder was left in the packaged conf:"
              grep -n '@share@' "$conf"
              exit 1
            fi

            want() {
              grep -qF "$1" "$conf" || { echo "the conf is missing: $1"; exit 1; }
            }

            # A trimmed frame collapses the texture and the text jumps
            want 'text_trim = false'
            want 'path = ${ddlc-hyprlock}/share/ddlc-hyprlock/just-monika.png'
            want 'path = ${ddlc-hyprlock}/share/ddlc-hyprlock/dialog-box.png'
            want 'cat "''${XDG_RUNTIME_DIR:-/tmp}/hypr-ddlc/frame"'
            want 'cat "''${XDG_RUNTIME_DIR:-/tmp}/hypr-ddlc/name"'
            touch $out
          '';

          # Enabling the module has to be enough: the config written, the engine installed, the
          # dialog present, and the plain lock genuinely plain
          module-wiring =
            let
              wiring = import ./nix/module-test.nix {
                inherit lib pkgs;
                module = self.homeManagerModules.default;
              };
            in
            pkgs.runCommand "module-wiring"
              {
                nativeBuildInputs = [ pkgs.jq ];
                dump = builtins.toJSON wiring;
                passAsFile = [ "dump" ];
              }
              ''
                want() { jq -e "$1" "$dumpPath" >/dev/null || { echo "module wiring: $2"; exit 1; }; }

                want '.package | test("ddlc-hyprlock")' "the engine is not installed"
                # The name is baked into the wrapper, so changing it has to move the path
                want '.package != .tunedPackage' "the name does not reach the package"
                want '.hyprlockEnabled' "hyprlock itself is not enabled"

                want '.labels == 5' "the dialog labels are not there"
                want '.images == 1' "the dialog box image is not there"
                want '[.texts[] | select(test("hypr-ddlc/frame"))] | length == 1' \
                  "nothing reads the rendered frame"
                want '.background | test("/nix/store/.*ddlc-hyprlock")' \
                  "the background does not come from the package"
                want '.font == "Doki"' "the font does not reach the labels"
                want '.lockCommand | test("ddlc-hyprlock.*lock$")' "a lock does not run the engine"

                # The flash that needs nothing is the default, and it stays quiet
                want '.flash == "hyprctl"' "the default flash is not the dependency-free one"
                want '.warnings == []' "a flash on Hyprland warns about something"
                want '.failedAssertions == []' "the default configuration does not hold"
                # Handing over the package is what picks that mode — no second option to set
                want '.shaderFlash == "screen-shader"' "the screen-shader package does not select its mode"
                # …and picking it without the package has to fail loudly rather than silently
                want '.shaderlessAssertions == 1' "screen-shader without the package is accepted"
                want '.noCompositorWarnings == 1' "a flash with no compositor to paint it is not flagged"

                # dialog = false is the whole point of the option: no engine, no polling
                want '.plainLabels == 3' "the plain lock still carries dialog labels"
                want '.plainImages == 0' "the plain lock still draws the dialog box"
                want '[.plainTexts[] | select(test("hypr-ddlc"))] | length == 0' \
                  "the plain lock still polls the state directory"
                want '.plainLockCommand | test("ddlc-hyprlock") | not' \
                  "the plain lock still goes through the engine"
                want '.plainPackages == []' "the plain lock still installs the engine"

                want '.offPackages == []' "the engine is installed while disabled"
                want '.offHyprlock | not' "hyprlock is enabled while disabled"
                want '.offSettings == []' "the config is written while disabled"
                touch $out
              '';

          scripts-lint =
            pkgs.runCommand "scripts-lint"
              {
                nativeBuildInputs = [
                  pkgs.shellcheck
                  pkgs.shfmt
                ];
              }
              ''
                files="${engine} ${testsDir}/run.sh ${testsDir}/live.sh ${installer}"
                # shellcheck disable=SC2086
                shellcheck $files
                # shellcheck disable=SC2086
                shfmt -d -i 2 -ci $files
                touch $out
              '';
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            hyprlock
            shellcheck
            shfmt
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
