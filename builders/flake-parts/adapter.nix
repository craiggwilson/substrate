# Flake-parts adapter for substrate
# Builds the flake from the outputs substrate's registered builders produce
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
  systems = settings.systems;

  # Under flake-parts, each per-system output name becomes a flake output
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

  # Under flake-parts, each global output name becomes a flake-level output
  flake =
    let
      builderArgs = {
        inherit inputs;
        substrate = config.substrate;
      };
    in
    lib.mapAttrs (_: builders: buildAndMerge builderArgs builders) outputs.global;
}
