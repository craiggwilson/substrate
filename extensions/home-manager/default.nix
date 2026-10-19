{ lib, config, ... }:
let
  inherit (config.substrate) settings;
  slib = config.substrate.lib;

  # All overlays come from settings.overlays (extensions add theirs there too)
  allOverlays = settings.overlays;

  # Home Manager configurations exist only for users of home-only hosts
  # (usersOnly = true); users of system hosts are delivered by the
  # host-integration contribution inside the host's own configuration.
  # A user attached to no host builds nothing: substrate never produces a
  # host-less ("vanilla") Home Manager configuration.
  mkHomeConfigurations =
    {
      inputs,
      # Falls back to the consumer's inputs so a builder that supplies only
      # those still builds configurations; it just resolves home-manager and
      # nixpkgs from the consumer's pins rather than substrate's.
      coreInputs ? inputs,
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
            (settings.homeManager.modules or [ ])
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

  # Integrates Home Manager into host configurations (e.g., NixOS, nix-darwin).
  # Registered as a contribution per host class, so host builders need no
  # knowledge of this extension. The body is identical for each; only the
  # home-manager module that plugs it in differs, because NixOS and nix-darwin
  # each ship their own.
  contributeToHosts =
    {
      inputs,
      coreInputs ? inputs,
      substrate,
      hostname,
      hostcfg,
      userConfigs,
      homeManagerModule,
      pkgs,
      ...
    }:
    let

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
      homeManagerModule
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
            sharedModules = settings.homeManager.modules or [ ];
            users = lib.listToAttrs (
              lib.map (usercfg: {
                inherit (usercfg) name;
                value = mkHomeManagerUserModule hostcfg usercfg;
              }) userConfigs
            );
          };
      }
    ];

  # One body, two host classes. Each entry resolves the module that plugs Home
  # Manager into that class; nothing downstream needs to know the difference.
  #
  # Resolved here rather than at the point of use so a configuration with
  # neither host class imported never reaches `resolveInput` for a role it has
  # no use for.
  homeManagerModule =
    class: coreInputs:
    let
      homeManagerInput = slib.resolveInput "home-manager" coreInputs;
    in
    if class == "nixos" then
      homeManagerInput.nixosModules.home-manager
    else
      homeManagerInput.darwinModules.home-manager;

  toNixos =
    ctx: contributeToHosts (ctx // { homeManagerModule = homeManagerModule "nixos" ctx.coreInputs; });

  toDarwin =
    ctx: contributeToHosts (ctx // { homeManagerModule = homeManagerModule "darwin" ctx.coreInputs; });
in
{
  options.substrate.settings.homeManager.modules = lib.mkOption {
    type = lib.types.listOf lib.types.deferredModule;
    description = ''
      External home-manager modules to include in all home-manager
      configurations, ahead of anything the finder selects. Was
      `substrate.settings.homeManagerModules`.
    '';
    default = [ ];
  };

  # Declared here rather than by a publishing extension: the type that fits
  # home-manager modules is this extension's to state.
  options.substrate.publish.homeManagerModules = lib.mkOption {
    type = lib.types.attrsOf slib.publishedModuleType;
    default = { };
    description = ''
      home-manager modules exposed to consumers under the `homeManagerModules`
      output. Was `substrate.modules.publish.homeManagerModules`.
    '';
  };

  config.substrate = {
    settings.supportedClasses = [ "homeManager" ];
    settings.contributors = [
      {
        class = "nixos";
        contribute = toNixos;
      }
      {
        class = "darwin";
        contribute = toDarwin;
      }
    ];

    settings.publishers.homeManagerModules = {
      scope = "global";
      output = "homeManagerModules";
      build = { substrate, ... }: substrate.publish.homeManagerModules;
    };

    outputs.global.homeConfigurations = [
      {
        build =
          {
            inputs,
            coreInputs ? inputs,
            substrate,
          }:
          mkHomeConfigurations { inherit inputs coreInputs substrate; };
      }
    ];
  };
}
