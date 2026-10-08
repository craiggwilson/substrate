{ lib, config, ... }:
let
  inherit (config.substrate) settings;
  slib = config.substrate.lib;

  # All overlays come from settings.overlays (extensions add theirs there too)
  allOverlays = settings.overlays or [ ];

  # Home Manager configurations exist only for users of home-only hosts
  # (usersOnly = true); users of system hosts are delivered by the
  # host-integration contribution inside the host's own configuration.
  # A user attached to no host builds nothing: substrate never produces a
  # host-less ("vanilla") Home Manager configuration.
  mkHomeConfigurations =
    {
      inputs,
      coreInputs,
      substrate,
    }:
    let
      nixpkgsInput = slib.resolveInput "nixpkgs" coreInputs;
      homeManagerInput = slib.resolveInput "home-manager" coreInputs;

      # One host-scoped Home Manager configuration, keyed <user>@<host>.
      # It sees the host's architecture, nixpkgs config, name (module
      # argument `host`), full host config (`hostcfg`), and host tags (via
      # the finder and hasTag), exactly as host-integrated users do inside
      # a NixOS build.
      mkConfig =
        {
          userName,
          usercfg,
          hostname,
          hostcfg,
        }:
        let
          userPkgs = import nixpkgsInput {
            localSystem = hostcfg.system;
            overlays = allOverlays;
            config = settings.nixpkgsConfig // usercfg.nixpkgsConfig // hostcfg.nixpkgsConfig;
          };
          extraArgs = slib.extraArgsGenerator {
            inherit
              usercfg
              hostcfg
              inputs
              ;
            pkgs = userPkgs;
          };
          contributedModules = slib.contributionsFor "homeManager" {
            inherit
              inputs
              coreInputs
              substrate
              userName
              usercfg
              hostcfg
              hostname
              ;
            pkgs = userPkgs;
          };
        in
        homeManagerInput.lib.homeManagerConfiguration {
          pkgs = userPkgs;
          extraSpecialArgs = extraArgs // {
            inherit
              inputs
              hostcfg
              userName
              ;
            host = hostname;
          };
          modules =
            (settings.homeManagerModules or [ ])
            ++ (slib.findModulesForClass "homeManager" [
              hostcfg
              usercfg
            ])
            ++ contributedModules;
        };
    in
    lib.mergeAttrsList (
      lib.mapAttrsToList (
        hostname: hostcfg:
        if hostcfg.usersOnly then
          lib.listToAttrs (
            lib.map (
              userName:
              lib.nameValuePair "${userName}@${hostname}" (mkConfig {
                inherit
                  userName
                  hostname
                  hostcfg
                  ;
                usercfg = substrate.users.${userName};
              })
            ) hostcfg.users
          )
        else
          { }
      ) substrate.hosts
    );

  # Integrates Home Manager into host configurations (e.g., NixOS).
  # Registered as a nixos-class contribution so host builders need no
  # knowledge of this extension.
  contributeToHosts =
    {
      inputs,
      coreInputs,
      substrate,
      hostname,
      hostcfg,
      userConfigs,
      pkgs,
      ...
    }:
    let
      homeManagerInput = slib.resolveInput "home-manager" coreInputs;

      # User classes are consumed in both paths; NixOS-embedded users are user
      # configurations too, so homeManager-class contributions reach them here.
      contributedModulesFor =
        usercfg:
        slib.contributionsFor "homeManager" {
          inherit
            inputs
            coreInputs
            substrate
            pkgs
            usercfg
            ;
          userName = usercfg.name;
        };
    in
    [
      homeManagerInput.nixosModules.home-manager
      {
        home-manager =
          let
            mkHomeManagerUserModule = hostcfg: usercfg: {
              imports =
                (slib.findModulesForClass "homeManager" [
                  hostcfg
                  usercfg
                ])
                ++ contributedModulesFor usercfg;
              # Extra args for home-manager modules (e.g., hasTag from tags extension).
              # userName matches the host-integration users map key, mirroring the
              # module argument host-scoped configs receive.
              _module.args =
                slib.extraArgsGenerator {
                  inherit
                    hostcfg
                    usercfg
                    inputs
                    pkgs
                    ;
                }
                // {
                  userName = usercfg.name;
                };
            };
          in
          {
            # Home Manager uses the system's pkgs (resolved from substrate's
            # locked inputs, rewired by the consumer via
            # inputs.substrate.inputs.nixpkgs.follows), keeping the locked
            # default coherent when the consumer rewires nixpkgs.
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
                inherit (usercfg) name;
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
    settings.contributors = [
      {
        class = "nixos";
        contribute = contributeToHosts;
      }
    ];

    outputs.global.homeConfigurations = [
      {
        build =
          {
            inputs,
            coreInputs,
            substrate,
          }:
          mkHomeConfigurations { inherit inputs coreInputs substrate; };
      }
    ];
  };
}
