# A bare shell file: the path-entry form. Substrate imports it with the entry
# context, so this reads the same as a function entry would.
{ pkgs, ... }:
pkgs.mkShell {
  packages = [ pkgs.hello ];
}
