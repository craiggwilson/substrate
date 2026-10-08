{ lib, config, ... }:
let
  inherit (config.substrate) settings;
  slib = config.substrate.lib;

  # All overlays come from settings.overlays
  allOverlays = settings.overlays or [ ];

  mkNixosConfigurations =
    {
      inputs,
      coreInputs,
      substrate,
    }:
    let
      nixpkgsInput = slib.resolveInput "nixpkgs" coreInputs;

      pkgsConfigFor = hostcfg: settings.nixpkgsConfig // hostcfg.nixpkgsConfig;

      # Home-only hosts (usersOnly = true) carry users and tags but declare
      # no operating system to build; skipped here.
      systemHosts = lib.filterAttrs (_: hostcfg: !hostcfg.usersOnly) substrate.hosts;

      # One package set per distinct (system, nixpkgs config) pair, shared
      # across hosts. Handed to nixosSystem via nixpkgs.pkgs, so the
      # configuration's own pkgs and the pkgs passed to extraArgsGenerators
      # are literally the same value — no duplicated evaluation, no
      # divergence. Config is baked in at import, hence part of the key.
      pkgsInstances = lib.foldl' (
        acc: hostcfg:
        let
          key = {
            inherit (hostcfg) system;
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
      ) [ ] (builtins.attrValues systemHosts);

      hostPkgsFor =
        hostcfg:
        (builtins.head (
          lib.filter (
            i:
            i.key == {
              inherit (hostcfg) system;
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
          inherit (usercfg) name;
          group = lib.mkDefault "users";
        };

        nixosUsers = lib.listToAttrs (
          lib.map (
            user:
            let
              usercfg = substrate.users.${user};
            in
            {
              inherit (usercfg) name;
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

        # Modules contributed by other extensions for the nixos class
        # (e.g., home-manager integration, secrets placement).
        contributedModules = slib.contributionsFor "nixos" {
          inherit
            inputs
            coreInputs
            substrate
            hostname
            hostcfg
            userConfigs
            ;
          pkgs = hostPkgs;
        };

        # Inputs are expected to be flake-shaped; nixpkgs exposes nixosSystem
        # on its lib output.
        inherit (nixpkgsInput.lib) nixosSystem;
      in
      nixosSystem {
        specialArgs = {
          inherit inputs hostcfg;
          host = hostname;
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
    ) systemHosts;
in
{
  options.substrate.settings.nixosModules = lib.mkOption {
    type = lib.types.listOf lib.types.deferredModule;
    description = "External NixOS modules to include in all NixOS configurations.";
    default = [ ];
  };

  config.substrate = {
    settings.supportedClasses = [ "nixos" ];

    outputs.global.nixosConfigurations = [
      {
        build =
          {
            inputs,
            coreInputs,
            substrate,
          }:
          mkNixosConfigurations { inherit inputs coreInputs substrate; };
      }
    ];
  };
}
