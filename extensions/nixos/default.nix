{ lib, config, ... }:
let
  settings = config.substrate.settings;
  slib = config.substrate.lib;

  # All overlays come from settings.overlays
  allOverlays = settings.overlays or [ ];

  mkNixosConfigurations =
    { inputs, substrate }:
    let
      nixpkgsInput = slib.resolveInput "nixpkgs" inputs;

      pkgsConfigFor = hostcfg: settings.nixpkgsConfig // hostcfg.nixpkgsConfig;

      # One package set per distinct (system, nixpkgs config) pair, shared
      # across hosts. Handed to nixosSystem via nixpkgs.pkgs, so the
      # configuration's own pkgs and the pkgs passed to extraArgsGenerators
      # are literally the same value — no duplicated evaluation, no
      # divergence. Config is baked in at import, hence part of the key.
      pkgsInstances = lib.foldl' (
        acc: hostcfg:
        let
          key = {
            system = hostcfg.system;
            config = pkgsConfigFor hostcfg;
          };
        in
        if builtins.any (i: i.key == key) acc then
          acc
        else
          acc
          ++ [
            {
              inherit key;
              pkgs = import nixpkgsInput {
                inherit (key) system config;
                overlays = allOverlays;
              };
            }
          ]
      ) [ ] (builtins.attrValues substrate.hosts);

      hostPkgsFor =
        hostcfg:
        (builtins.head (
          lib.filter (
            i:
            i.key == {
              system = hostcfg.system;
              config = pkgsConfigFor hostcfg;
            }
          ) pkgsInstances
        )).pkgs;
    in
    lib.mapAttrs (
      hostname: hostcfg:
      let
        hostPkgs = hostPkgsFor hostcfg;

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
          pkgs = hostPkgs;
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
            pkgs = hostPkgs;
          }
        ) settings.perHostContributors;
      in
      nixpkgsInput.lib.nixosSystem {
        specialArgs = {
          inherit inputs hostcfg;
        };
        modules = [
          {
            # Using the shared pkgs set means nixpkgs.overlays and
            # nixpkgs.hostPlatform are not read here; overlays already come in
            # via settings.overlays (baked into the pkgs instances above).
            nixpkgs.pkgs = hostPkgs;
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
