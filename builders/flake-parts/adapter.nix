# Flake-parts adapter for substrate
# Provides core flake outputs and calls registered output builders
{
  lib,
  config,
  inputs,
  ...
}:
let
  settings = config.substrate.settings;
  outputs = config.substrate.outputs;
  slib = config.substrate.lib;
  nixpkgsInput = slib.resolveInput "nixpkgs" inputs;

  # All overlays come from settings.overlays (extensions add theirs there too)
  allOverlays = settings.overlays or [ ];

  # Build all builders for an output and merge results
  buildAndMerge =
    builderArgs: builders: lib.foldl' (acc: builder: acc // (builder.build builderArgs)) { } builders;
in
{
  imports = [
    ./checks.nix
  ];

  systems = settings.systems;

  # Build per-system outputs under each per-system flake output name
  perSystem =
    { system, ... }:
    let
      pkgs = import nixpkgsInput {
        inherit system;
        overlays = allOverlays;
        config = config.substrate.settings.nixpkgsConfig;
      };
      builderArgs = {
        inherit pkgs system inputs;
        substrate = config.substrate;
      };
    in
    lib.mapAttrs (_: builders: buildAndMerge builderArgs builders) outputs.perSystem;

  # Build global outputs under each flake-level output name
  flake =
    let
      builderArgs = {
        inherit inputs;
        substrate = config.substrate;
      };
    in
    lib.mapAttrs (_: builders: buildAndMerge builderArgs builders) outputs.global;
}
