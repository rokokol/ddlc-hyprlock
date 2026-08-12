# hyprlock settings attrset -> hyprlock.conf text. Home Manager renders the same attrset
# with its own generator, so this exists for the two consumers HM cannot serve: the conf
# inside the package (for `hyprlock -c`) and the committed dist/ for an install without Nix
#
# The shape is the one hyprlock reads: an attrset is a section, a list of attrsets is that
# section repeated (there are several labels), a list of strings is the key repeated
{ lib }:

let
  value =
    v:
    if lib.isBool v then
      lib.boolToString v
    else if lib.isString v then
      v
    else
      toString v;

  # Keys are sorted by mapAttrsToList, so the same attrset always renders byte-identically
  entry =
    indent: name: v:
    if lib.isAttrs v then
      section indent name v
    else if lib.isList v then
      lib.concatMapStrings (
        item: if lib.isAttrs item then section indent name item else "${indent}${name} = ${value item}\n"
      ) v
    else
      "${indent}${name} = ${value v}\n";

  section =
    indent: name: attrs:
    "${indent}${name} {\n"
    + lib.concatStrings (lib.mapAttrsToList (entry "${indent}    ") attrs)
    + "${indent}}\n";
in
settings: lib.concatStrings (lib.mapAttrsToList (entry "") settings)
