# Development shells built with mkShell, published under the `devShells` output.
{
  lib,
  config,
  inputs,
  ...
}:
let
  publishCfg = config.substrate.publish.devShells or { };

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
in
{
  # Entries are named by their attribute key, so a shell is called what you wrote
  # rather than what its file was called.
  options.substrate.shells = lib.mkOption {
    type = lib.types.attrsOf entryType;
    default = { };
    description = ''
      Shell definitions available to this configuration. An entry is either a
      path to a shell definition, which is imported with
      { pkgs, system, lib, inputs, substrate }, or a function of the same set.
      Shells are exposed to consumers only when assigned under
      `substrate.publish.devShells`.
    '';
  };

  options.substrate.publish.devShells = lib.mkOption {
    type = lib.types.attrsOf entryType;
    default = { };
    description = ''
      Shells exposed to consumers under the `devShells` output, as a
      name-to-entry attribute set. An entry is either a path to a shell
      definition, which is imported with
      { pkgs, system, lib, inputs, substrate }, or a function of the same set.
      Was `substrate.shells.publish`.
    '';
  };

  config.substrate.settings.publishers.devShells = {
    scope = "perSystem";
    output = "devShells";
    build = args: mkShells (args // { shells = publishCfg; });
  };
}
