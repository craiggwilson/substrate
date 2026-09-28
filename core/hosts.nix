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
            usersOnly = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Whether this host carries only user configurations and no
                operating system of its own. Set true to declare a home-only
                host: a machine substrate does not administer its system for
                (a personal machine, a company laptop). Such hosts build no
                system output, but their name, tags, system, and nixpkgsConfig
                still shape the host-scoped Home Manager configurations of
                their users (keyed <user>@<host>), which receive the host as
                module arguments exactly like host-integrated users do.
              '';
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
