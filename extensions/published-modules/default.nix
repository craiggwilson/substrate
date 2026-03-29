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
      description = "Named NixOS modules to publish as the nixosModules flake output.";
    };

    homeManagerModules = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Named Home Manager modules to publish as the homeManagerModules flake output.";
    };

    substrateModules = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Named substrate modules to publish as the substrateModules flake output.";
    };
  };

  config.substrate.outputs = {
    nixosModules = lib.mkIf hasNixos [
      {
        type = "global";
        build = { ... }: publish.nixosModules;
      }
    ];

    homeManagerModules = lib.mkIf hasHomeManager [
      {
        type = "global";
        build = { ... }: publish.homeManagerModules;
      }
    ];

    substrateModules = lib.mkIf hasSubstrate [
      {
        type = "global";
        build = { ... }: publish.substrateModules;
      }
    ];
  };
}
