# The other file style: written against `pkgs` rather than a callPackage argument.
# nixpkgs exposes `pkgs` on the package set, so callPackage binds it here too and
# both file conventions work interchangeably.
{ pkgs, ... }:
pkgs.runCommand "pkgs-style" { } ''
  mkdir -p $out
  touch $out/pkgs-style
''
