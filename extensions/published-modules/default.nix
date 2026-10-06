{ lib, config, ... }:
let
  publish = config.substrate.settings.publish;

  hasNixos = publish.nixosModules != { };
  hasHomeManager = publish.homeManagerModules != { };
  hasSubstrate = publish.substrateModules != { };
in
{
  options.substrate.settings.publish = {
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
        build = { ... }: publish.nixosModules;
      }
    ];

    homeManagerModules = lib.mkIf hasHomeManager [
      {
        build = { ... }: publish.homeManagerModules;
      }
    ];

    substrateModules = lib.mkIf hasSubstrate [
      {
        build = { ... }: publish.substrateModules;
      }
    ];
  };
}
