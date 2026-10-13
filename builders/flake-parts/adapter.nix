# Flake-parts adapter for substrate
# Builds the flake from the outputs substrate's registered builders produce
{
  lib,
  config,
  inputs,
  coreInputs,
  ...
}:
let
  inherit (config.substrate) settings outputs;

  # flake-parts has already evaluated the configuration by the time this runs,
  # so there is nothing left to evaluate — `fromConfig` rather than
  # `fromModule`.
  c = (import ../common.nix).fromConfig {
    inherit
      coreInputs
      inputs
      lib
      ;
    inherit (config) substrate;
  };
in
{
  inherit (settings) systems;

  # Under flake-parts, each per-system output name becomes a flake output.
  # One package set per system, shared across every output name.
  perSystem =
    { system, ... }:
    let
      pkgs = c.pkgsFor system;
    in
    lib.mapAttrs (_: builders: c.merge (c.perSystemArgs system pkgs) builders) outputs.perSystem;

  # Each global output name becomes a flake-level output.
  flake = lib.mapAttrs (_: builders: c.merge c.globalArgs builders) outputs.global;
}
