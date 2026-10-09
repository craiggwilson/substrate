# A package written as an ordinary substrate module. Nothing marks this out as a
# package file: it assigns an entry, exactly as any other module assigns an
# option.
_: {
  substrate.packages.publish.module-entry =
    { pkgs, ... }:
    pkgs.runCommand "module-entry" { } ''
      mkdir -p $out
      touch $out/module-entry
    '';
}
