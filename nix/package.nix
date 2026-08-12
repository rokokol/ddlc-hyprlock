# The dialog engine, the assets it speaks from, and the hyprlock config that lays the
# labels out for it. Geometry is why the two ship together: the labels are pinned by a
# constant texture size, so the engine has to wrap the text to exactly the width the
# config gave the text area
#
# journalctl is deliberately NOT a runtime input — the follower reads the journal of the
# running system, and a second systemd here would read nothing. screen-shader is optional
# by design: the engine degrades the glitch to text-only when the command is not there
{
  lib,
  stdenvNoCC,
  makeWrapper,
  writeText,
  bash,
  coreutils,
  gawk,
  # ddlc-palette's bare attrset (hex without the "#") — the flake passes it in
  palette,
  # The locker to run. null leaves it to whatever `hyprlock` is on PATH at lock time
  hyprlock ? null,
  # How the whole screen flashes on a glitch: "hyprctl" sets the shipped shader and clears it
  # again, "screen-shader" hands the flash to that command, "none" leaves the glitch text-only
  flash ? "hyprctl",
  # Only read by the screen-shader mode; that command has to come from the caller
  screenShader ? null,
  glitchShader ? null,
  # withDialog, not dialog: callPackage fills any argument nixpkgs has an attribute for, and
  # `pkgs.dialog` is the TUI — the default would silently become a package
  withDialog ? true,
  glitch ? withDialog,
  name ? "Monika",
  characterFile ? null,
  font ? "Doki",
  background ? null,
  dialogImage ? null,
  quotes ? null,
  reentry ? null,
  stateDir ? "\${XDG_RUNTIME_DIR:-/tmp}/hypr-ddlc",
  pollMs ? 100,
  placeholderText ? null,
  failText ? null,
}:

let
  # Each file isolated, so a README edit rebuilds nothing
  file =
    fileName: p:
    builtins.path {
      name = fileName;
      path = p;
    };

  engine = file "ddlc-hyprlock.sh" ../ddlc-hyprlock.sh;
  assets = {
    "just-monika.png" = file "just-monika.png" ../assets/just-monika.png;
    "dialog-box.png" = file "dialog-box.png" ../assets/dialog-box.png;
    "monika-talk.txt" = file "monika-talk.txt" ../assets/monika-talk.txt;
    "monika-reentry.txt" = file "monika-reentry.txt" ../assets/monika-reentry.txt;
    "glitch.frag" = file "glitch.frag" ../shaders/glitch.frag;
  };

  share = "$out/share/ddlc-hyprlock";

  # An unset path means the shipped asset, which is a path only once $out is known
  pick = given: shipped: if given != null then toString given else "${share}/${shipped}";

  # Left out when unset, so config.nix's own defaults stay the single source of them
  overrides = lib.filterAttrs (_: v: v != null) {
    inherit placeholderText failText;
  };

  config = import ./config.nix (
    {
      inherit
        palette
        font
        stateDir
        pollMs
        ;
      dialog = withDialog;
      # @share@ rather than $out: the text is written by another derivation, where nothing
      # would expand it. installPhase substitutes it once $out is known
      background = if background != null then toString background else "@share@/just-monika.png";
      dialogImage = if dialogImage != null then toString dialogImage else "@share@/dialog-box.png";
    }
    // overrides
  );

  conf = writeText "hyprlock.conf.in" (import ./render.nix { inherit lib; } config.settings);

  # Only what the caller actually set, so the flag list ends without a dangling backslash
  extraFlags = lib.escapeShellArgs (
    lib.optionals (hyprlock != null) [
      "--set-default"
      "DDLC_HYPRLOCK_HYPRLOCK"
      (lib.getExe hyprlock)
    ]
    ++ lib.optionals (screenShader != null) [
      "--set-default"
      "DDLC_HYPRLOCK_SHADER"
      (lib.getExe screenShader)
    ]
    ++ lib.optionals (characterFile != null) [
      "--set-default"
      "DDLC_HYPRLOCK_CHR"
      (toString characterFile)
    ]
  );
in

stdenvNoCC.mkDerivation {
  pname = "ddlc-hyprlock";
  version = "1.0";

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ bash ];

  installPhase = ''
    runHook preInstall

    install -d ${share}
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (fileName: p: "install -m644 ${p} ${share}/${fileName}") assets
    )}

    substitute ${conf} ${share}/hyprlock.conf --subst-var-by share ${share}

    install -Dm755 ${engine} $out/bin/ddlc-hyprlock
    patchShebangs $out/bin

    # --set-default, not --set: an override from the environment still wins
    wrapProgram $out/bin/ddlc-hyprlock \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          gawk
        ]
      } \
      --set-default DDLC_HYPRLOCK_QUOTES ${pick quotes "monika-talk.txt"} \
      --set-default DDLC_HYPRLOCK_REENTRY ${pick reentry "monika-reentry.txt"} \
      --set-default DDLC_HYPRLOCK_NAME ${lib.escapeShellArg name} \
      --set-default DDLC_HYPRLOCK_TEXT_W ${toString config.textW} \
      --set-default DDLC_HYPRLOCK_FONT_PX ${toString config.fontPx} \
      --set-default DDLC_HYPRLOCK_POLL_MS ${toString pollMs} \
      --set-default DDLC_HYPRLOCK_GLITCH ${if glitch then "1" else "0"} \
      --set-default DDLC_HYPRLOCK_FLASH ${lib.escapeShellArg flash} \
      --set-default DDLC_HYPRLOCK_GLITCH_SHADER ${pick glitchShader "glitch.frag"} \
      ${extraFlags}

    runHook postInstall
  '';

  meta = {
    description = "The Doki Doki Literature Club lock screen for hyprlock, with Monika's dialog";
    homepage = "https://github.com/rokokol/ddlc-hyprlock";
    # MIT covers the code; the sprites and the dialogue are Team Salvato's
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "ddlc-hyprlock";
  };
}
