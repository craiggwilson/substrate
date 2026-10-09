# Two modules may contribute to the same package; the module system merges them.
_: {
  substrate.packages.publish.other-module-entry =
    { pkgs, ... }:
    pkgs.runCommand "other-module-entry" { } ''
      mkdir -p $out
      touch $out/other-module-entry
    '';
}
