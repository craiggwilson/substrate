# The module that publishes the `wrap` argument into a target configuration.
#
# `wrap` needs the configuration it belongs to, so it is defined here rather than
# by an extraArgsGenerator. A generator runs in the builder, outside the
# configuration being built, so there is no config for it to name; and nixpkgs
# passes argument values through verbatim rather than applying them, so a
# closure handed to a generator would arrive unapplied. A module argument is
# defined *inside* the configuration, which is the only place `config` is in
# scope — and it is the only way a contributor's hook can read the options
# declared next to the wrapper (secrets reads config.secretspec to find the
# manifest its scope belongs to).
#
# Import parameters:
#
#   contributors  the registry from substrate.settings.wrappers.contributors,
#                 closed over so contributors' options become spec keys and their
#                 hooks receive the build context below
#   usercfg       the substrate user configuration, or null for a host build.
#                 Neither builder passes this as a module argument, so it arrives
#                 from the contribution context.
#   force         publish with lib.mkForce. Set when this class's configuration
#                 is nested inside another's (Home Manager inside NixOS): both
#                 contributions then land in one module system, and the nested
#                 class has the more specific context, so it must win. Verified:
#                 two plain definitions of the same _module.args key conflict,
#                 mkDefault on both sides conflicts too, and mkForce wins in
#                 either module order.
{
  contributors,
  usercfg ? null,
  force ? false,
}:
{
  config,
  lib,
  pkgs,
  inputs,
  hostcfg,
  ...
}:
{
  _module.args.wrap = (if force then lib.mkForce else x: x) (
    import ./wrap.nix {
      inherit
        config
        contributors
        inputs
        lib
        pkgs
        hostcfg
        usercfg
        ;
    }
  );
}
