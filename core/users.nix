{ lib, ... }:
{
  options.substrate.users = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options =
            let
              parts = lib.match "([[:alnum:]]+)(@([[:alnum:]]*))?" name;
              name' = lib.elemAt parts 0;
              profile = lib.elemAt parts 2;
              profile' = if profile == null then "" else profile;
            in
            {
              name = lib.mkOption {
                description = "The name to use for the user account.";
                type = lib.types.str;
                default = name';
              };
              profile = lib.mkOption {
                description = "The profile of the user if one exists.";
                type = lib.types.str;
                default = profile';
              };
              nixpkgsConfig = lib.mkOption {
                type = lib.types.attrsOf lib.types.anything;
                description = "Additional nixpkgs configuration for this user's host-scoped package sets, merged over substrate.settings.nixpkgsConfig and under the host's nixpkgsConfig. Users on system hosts share the host's package set instead.";
                default = { };
              };

            };
        }
      )
    );
    default = { };
    description = "User specific configurations.";
  };
}
