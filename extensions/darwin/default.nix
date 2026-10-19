# nix-darwin hosts, as their own class alongside NixOS.
#
# Darwin is a class, not a variant of the NixOS one: a host declares its modules
# under `darwin` and only those are built. What the two share -- packages,
# overlays, checks, users, secrets, wrappers -- reaches a darwin host the same
# way it reaches a NixOS one, because an extension that targets a class says so
# in its own `contributors` entry and nothing here has to know about it.
#
# A host is a darwin host because its system is one. That check is the whole of
# the routing: a darwin host is handed `darwin`-class modules and nothing else,
# because a NixOS option does not exist in a nix-darwin configuration and would
# fail rather than be ignored.
{ lib, config, ... }:
let
  inherit (config.substrate) settings;
  slib = config.substrate.lib;

  isDarwin = host: builtins.match ".*-darwin" host.system != null;

  mkDarwinConfigurations =
    {
      inputs,
      # Falls back to the consumer's inputs, as the nixos extension does: a
      # builder that supplies only those still builds hosts, it just resolves
      # nixpkgs and nix-darwin from the consumer's pins.
      coreInputs ? inputs,
      substrate,
    }:
    let
      nixpkgsInput = slib.resolveInput "nixpkgs" coreInputs;
      nixDarwinInput = slib.resolveInput "nix-darwin" coreInputs;

      pkgsConfigFor = hostcfg: settings.nixpkgsConfig // hostcfg.nixpkgsConfig;

      # Users-only hosts carry users and modules but declare no operating
      # system, and a linux host has no darwin configuration to build. Both are
      # skipped before anything is evaluated, so importing this extension on a
      # linux-only configuration costs nothing.
      systemHosts = lib.filterAttrs (_: hostcfg: !hostcfg.usersOnly && isDarwin hostcfg) substrate.hosts;

      # One package set per distinct (system, nixpkgs config) pair, shared
      # across hosts, exactly as the nixos extension does it. Overlays have to
      # be baked in at import, so the config is part of the key.
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
                inherit (settings) overlays;
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
        userConfigs = map (user: substrate.users.${user}) hostcfg.users;

        # A host's own scope, and the scope of a host that has users -- the two
        # calls the nixos extension makes, made here for the darwin class.
        darwinModules = slib.findModulesForClass "darwin" [ hostcfg ];
        hostDarwinModules = slib.findModulesForClass "darwin" ([ hostcfg ] ++ userConfigs);

        darwinExtraArgs = slib.extraArgsGenerator {
          inherit hostcfg inputs;
          usercfg = null;
          pkgs = hostPkgs;
        };

        contributedModules = slib.contributionsFor "darwin" {
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

        inherit (nixDarwinInput) darwinSystem;
      in
      darwinSystem {
        specialArgs = {
          inherit inputs hostcfg;
          host = hostname;
        };
        modules = [
          {
            nixpkgs.pkgs = hostPkgs;
            networking.hostName = lib.mkDefault hostname;
            _module.args = darwinExtraArgs;
          }
        ]
        ++ settings.darwin.modules
        ++ slib.unique (darwinModules ++ hostDarwinModules)
        ++ contributedModules;
      }
    ) systemHosts;
in
{
  options.substrate.settings.darwin.modules = lib.mkOption {
    type = lib.types.listOf lib.types.deferredModule;
    description = ''
      External nix-darwin modules to include in all darwin configurations,
      ahead of anything the finder selects.
    '';
    default = [ ];
  };

  options.substrate.publish.darwinModules = lib.mkOption {
    type = lib.types.attrsOf slib.publishedModuleType;
    default = { };
    description = ''
      nix-darwin modules exposed to consumers under the `darwinModules` output.
    '';
  };

  config.substrate = {
    settings.supportedClasses = [ "darwin" ];

    settings.publishers.darwinModules = {
      scope = "global";
      output = "darwinModules";
      build = { substrate, ... }: substrate.publish.darwinModules;
    };

    outputs.global.darwinConfigurations = [
      {
        build =
          {
            inputs,
            coreInputs,
            substrate,
          }:
          mkDarwinConfigurations { inherit inputs coreInputs substrate; };
      }
    ];
  };
}
