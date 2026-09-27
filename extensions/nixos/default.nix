{ lib, config, ... }:
let
  settings = config.substrate.settings;
  slib = config.substrate.lib;

  # All overlays come from settings.overlays
  allOverlays = settings.overlays or [ ];

  mkNixosConfigurations =
    { inputs, substrate }:
    lib.mapAttrs (
      hostname: hostcfg:
      let
        mkNixosUser = usercfg: {
          isNormalUser = lib.mkDefault true;
          name = usercfg.name;
          group = lib.mkDefault "users";
        };

        nixosUsers = lib.listToAttrs (
          lib.map (
            user:
            let
              usercfg = substrate.users.${user};
            in
            {
              name = usercfg.name;
              value = mkNixosUser usercfg;
            }
          ) hostcfg.users
        );

        hostNixosModules = slib.findModulesForClass "nixos" [ hostcfg ];

        userConfigs = lib.map (user: substrate.users.${user}) hostcfg.users;
        userNixosModules = slib.findModulesForClass "nixos" ([ hostcfg ] ++ userConfigs);

        # Extra args for NixOS modules (e.g., hasTag from tags extension)
        nixosExtraArgs = slib.extraArgsGenerator {
          inherit hostcfg inputs;
          usercfg = null;
        };

        # Modules contributed by other extensions (e.g., home-manager integration)
        contributedModules = lib.concatMap (
          f:
          f {
            inherit
              inputs
              substrate
              hostname
              hostcfg
              userConfigs
              ;
          }
        ) settings.perHostContributors;
      in
      inputs.nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs hostcfg;
        };
        modules = [
          {
            nixpkgs = {
              overlays = allOverlays;
              hostPlatform = hostcfg.system;
            };
            networking.hostName = lib.mkDefault hostname;
            _module.args = nixosExtraArgs;
          }
          { users.users = nixosUsers; }
        ]
        ++ settings.nixosModules
        ++ slib.unique (hostNixosModules ++ userNixosModules)
        ++ contributedModules;
      }
    ) substrate.hosts;
in
{
  options.substrate.settings.nixosModules = lib.mkOption {
    type = lib.types.listOf lib.types.deferredModule;
    description = "External NixOS modules to include in all NixOS configurations.";
    default = [ ];
  };

  config.substrate = {
    settings.supportedClasses = [ "nixos" ];

    outputs.nixosConfigurations = [
      {
        type = "global";
        build = { inputs, substrate }: mkNixosConfigurations { inherit inputs substrate; };
      }
    ];
  };
}
