{ lib, config, ... }:
let
  modulesCfg = config.substrate.modules or { };

  publishCfg = modulesCfg.publish or { };

  hasNixos = publishCfg.nixosModules != { };
  hasHomeManager = publishCfg.homeManagerModules != { };
  hasSubstrate = publishCfg.substrateModules != { };
in
{
  options.substrate.modules.publish = {
    nixosModules = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Named NixOS modules to publish under the nixosModules output name.";
    };

    homeManagerModules = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Named Home Manager modules to publish under the homeManagerModules output name.";
    };

    substrateModules = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Named substrate modules to publish under the substrateModules output name.";
    };
  };

  config.substrate.outputs.global = {
    nixosModules = lib.mkIf hasNixos [
      {
        build = _: publishCfg.nixosModules;
      }
    ];

    homeManagerModules = lib.mkIf hasHomeManager [
      {
        build = _: publishCfg.homeManagerModules;
      }
    ];

    substrateModules = lib.mkIf hasSubstrate [
      {
        build = _: publishCfg.substrateModules;
      }
    ];
  };
}
