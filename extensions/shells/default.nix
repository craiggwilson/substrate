# Development shells built with mkShell, published under the `devShells` output.
#
# Orthogonal to the devenv extension: that one builds shells with devenv, this
# one with mkShell. Both write to `devShells`, so a configuration may load
# either or both — they just cannot claim the same shell name.
{
  lib,
  config,
  inputs,
  ...
}:
let
  shellsCfg = config.substrate.shells or { };

  entryType = lib.types.either (lib.types.functionTo lib.types.raw) lib.types.path;

  # Every entry is a function of the context a shell needs, or a path to one. A
  # shell is built per system, so `pkgs` is that system's package set — which,
  # unlike a package entry, the builder can supply directly. Write function
  # entries as `{ pkgs, ... }: ...` so they tolerate additions to this set.
  entryArgs =
    {
      pkgs,
      system,
      ...
    }:
    {
      inherit (config) substrate;
      inherit
        lib
        inputs
        pkgs
        system
        ;
      inherit (pkgs) stdenv;
    };

  # A path entry is imported with the context, so a shell file reads
  # `{ pkgs, ... }: pkgs.mkShell { ... }` whether it arrives as a path or as a
  # function. A function entry receives the context and decides for itself.
  runEntry = entry: context: if lib.isFunction entry then entry context else import entry context;

  mkShells = args: lib.mapAttrs (_: entry: runEntry entry (entryArgs args)) args.shells;

  published = shellsCfg.publish or { };
in
{
  # Entries are named by their attribute key, so a shell is called what you wrote
  # rather than what its file was called.
  options.substrate.shells = {
    internal = lib.mkOption {
      type = lib.types.attrsOf entryType;
      default = { };
      description = ''
        Shells substrate defines but does not publish, as a name-to-entry
        attribute set. An entry is either a path to a shell definition, which is
        imported with { pkgs, system, lib, inputs, substrate }, or a function of
        the same set.
      '';
    };

    publish = lib.mkOption {
      type = lib.types.attrsOf entryType;
      default = { };
      description = ''
        Shells exposed to consumers under the `devShells` output, as a
        name-to-entry attribute set. An entry is either a path to a shell
        definition, which is imported with
        { pkgs, system, lib, inputs, substrate }, or a function of the same set.
      '';
    };
  };

  config.substrate.outputs.perSystem.devShells = lib.mkIf (published != { }) [
    {
      build = args: mkShells (args // { shells = published; });
    }
  ];
}
