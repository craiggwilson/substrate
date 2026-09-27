{ lib, config, ... }:
let
  settings = config.substrate.settings;
  slib = config.substrate.lib;

  # All overlays come from settings.overlays (extensions add theirs there too)
  allOverlays = settings.overlays or [ ];

  mkHomeConfigurations =
    { inputs, substrate }:
    let
      nixpkgsInput = slib.resolveInput "nixpkgs" inputs;
      homeManagerInput = slib.resolveInput "home-manager" inputs;
    in
    lib.mapAttrs (
      userName: usercfg:
      let
        userPkgs = import nixpkgsInput {
          localSystem = usercfg.system;
          overlays = allOverlays;
          config = settings.nixpkgsConfig // usercfg.nixpkgsConfig;
        };
        extraArgs = slib.extraArgsGenerator {
          inherit usercfg inputs;
          hostcfg = null;
          pkgs = userPkgs;
        };
        contributedModules = lib.concatMap (
          f:
          f {
            inherit
              inputs
              substrate
              userName
              usercfg
              ;
            pkgs = userPkgs;
          }
        ) settings.perUserContributors;
      in
      homeManagerInput.lib.homeManagerConfiguration {
        pkgs = userPkgs;
        extraSpecialArgs = extraArgs // {
          inherit inputs;
        };
        modules =
          (settings.homeManagerModules or [ ])
          ++ (slib.findModulesForClass "homeManager" [ usercfg ])
          ++ contributedModules;
      }
    ) substrate.users;

  # Integrates Home Manager into host configurations (e.g., NixOS).
  # Pushed as a per-host contributor so host builders need no knowledge of this extension.
  contributeToHosts =
    {
      inputs,
      hostname,
      hostcfg,
      userConfigs,
      pkgs,
      ...
    }:
    let
      homeManagerInput = slib.resolveInput "home-manager" inputs;
    in
    [
      homeManagerInput.nixosModules.home-manager
      {
        home-manager =
          let
            mkHomeManagerUserModule = hostcfg: usercfg: {
              imports = slib.findModulesForClass "homeManager" [
                hostcfg
                usercfg
              ];
              # Extra args for home-manager modules (e.g., hasTag from tags extension)
              _module.args = slib.extraArgsGenerator {
                inherit
                  hostcfg
                  usercfg
                  inputs
                  pkgs
                  ;
              };
            };
          in
          {
            useGlobalPkgs = lib.mkDefault true;
            useUserPackages = lib.mkDefault true;
            backupFileExtension = lib.mkDefault "bak";
            extraSpecialArgs = {
              inherit inputs hostcfg;
              host = hostname;
            };
            sharedModules = settings.homeManagerModules or [ ];
            users = lib.listToAttrs (
              lib.map (usercfg: {
                name = usercfg.name;
                value = mkHomeManagerUserModule hostcfg usercfg;
              }) userConfigs
            );
          };
      }
    ];
in
{
  options.substrate.settings = {
    homeManagerModules = lib.mkOption {
      type = lib.types.listOf lib.types.deferredModule;
      description = "External home-manager modules to include in all home-manager configurations.";
      default = [ ];
    };
  };

  config.substrate = {
    settings.supportedClasses = [ "homeManager" ];
    settings.perHostContributors = [ contributeToHosts ];

    outputs.global.homeConfigurations = [
      {
        build = { inputs, substrate }: mkHomeConfigurations { inherit inputs substrate; };
      }
    ];
  };
}
