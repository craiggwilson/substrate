{
  lib,
  config,
  ...
}:

{
  options.substrate.hosts = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            name = lib.mkOption {
              description = "The hostname of the machine.";
              type = lib.types.str;
              default = name;
            };
            system = lib.mkOption {
              type = lib.types.enum config.substrate.settings.systems;
              default = builtins.currentSystem;
            };
            nixpkgsConfig = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              description = "Additional nixpkgs configuration for this host's package set, merged over substrate.settings.nixpkgsConfig.";
              default = { };
            };
            users = lib.mkOption {
              type = lib.types.listOf (lib.types.enum (builtins.attrNames config.substrate.users));
              default = [ ];
            };

          };
        }
      )
    );
    default = { };
    description = "Host specific configurations.";
  };
}
