# Tests for the darwin extension.
#
# These assert the shape of what a darwin host produces, not a built
# configuration: CI is linux, so a nix-darwin system cannot be built here. What
# can be checked without one is everything on the way there -- which hosts are
# routed, which classes reach them, and which contributions load -- and that is
# what this covers. The first real build is the consumer's.
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib runTests;

  # The extension resolves `nix-darwin` and `nixpkgs` by role, so the eval has
  # to supply both as flake-shaped inputs. Nothing here builds anything, so the
  # stubs only have to be shaped like what `resolveInput` insists on --
  # `darwinSystem` hands its arguments straight back, which is what makes the
  # assertions below able to read what a host was built from.
  flakeShaped =
    name:
    {
      outPath = "/tmp/${name}-stub";
      inherit (pkgs) lib;
    }
    // lib.optionalAttrs (name == "darwin") {
      darwinSystem = args: args;
    };

  evalDarwin =
    modules:
    lib.evalModules {
      modules =
        testLib.extendedCoreModules
        ++ [
          ../../core/publish.nix
          ../../extensions/darwin
        ]
        ++ modules;
    };

  # Built the way a builder builds, with only the shape of the inputs it needs.
  built =
    eval:
    (builtins.head eval.config.substrate.outputs.global.darwinConfigurations).build {
      inputs = {
        nix-darwin = flakeShaped "darwin";
        nixpkgs = flakeShaped "nixpkgs";
      };
      # A builder always passes both; the extension falls back to `inputs` when
      # given only those, which is not what is being tested here.
      coreInputs = {
        nix-darwin = flakeShaped "darwin";
        nixpkgs = flakeShaped "nixpkgs";
      };
      substrate = eval.config.substrate;
    };

  # What one host was built from, which is the arguments darwinSystem was handed
  # rather than a system it produced.
  captured = eval: builtins.head (builtins.attrValues (built eval));

  tests = {
    darwinIsASupportedClass = {
      check =
        let
          eval = evalDarwin [ ];
        in
        lib.elem "darwin" eval.config.substrate.settings.supportedClasses;
    };

    # Routing is by system, and a host is either a darwin host or it is not.
    # Getting this wrong in the other direction -- building a linux host
    # through darwinSystem -- would fail loudly at evaluation, but only after
    # importing nix-darwin, so the check has to be here.
    onlyDarwinSystemsAreRouted = {
      check =
        let
          eval = evalDarwin [
            {
              config.substrate.hosts.apple.system = "aarch64-darwin";
              config.substrate.hosts.igloo.system = "x86_64-linux";
            }
          ];
          configs = built eval;
        in
        builtins.attrNames configs == [ "apple" ];
    };

    # A home-only host declares no operating system, so there is nothing to
    # route. A darwin system would change nothing about that.
    homeOnlyHostsAreNotRouted = {
      check =
        let
          eval = evalDarwin [
            {
              config.substrate.hosts.apple = {
                system = "aarch64-darwin";
                usersOnly = true;
              };
            }
          ];
        in
        builtins.attrNames (built eval) == [ ];
    };

    # What is handed to darwinSystem is what the darwin class selects. The
    # hostcfg module argument is what a module reads to find out where it
    # landed, and `host` is the name.
    aDarwinHostCarriesItsNameAndConfig = {
      check =
        let
          eval = evalDarwin [
            {
              config.substrate.hosts.apple.system = "aarch64-darwin";
            }
          ];
        in
        (captured eval).specialArgs.host == "apple"
        && (captured eval).specialArgs.hostcfg.system == "aarch64-darwin";
    };

    # A module written in darwin terms reaches a darwin host. This is the
    # whole point of darwin being a class rather than a variant.
    darwinModulesReachADarwinHost = {
      check =
        let
          eval = evalDarwin [
            {
              config.substrate.modules.programs.zfs.darwin = {
                marker = "darwin";
              };
              config.substrate.hosts.apple.system = "aarch64-darwin";
            }
          ];
          # Compared by identity rather than by content: a class leaf is read
          # through `nullOr deferredModule`, so what the builder is handed is a
          # wrapper around the module, not the module.
          inherit ((captured eval)) modules;
        in
        builtins.elem eval.config.substrate.modules.programs.zfs.darwin modules;
    };

    # `generic` modules are merged into every class, which is how a module
    # written once reaches both host classes.
    genericModulesReachADarwinHost = {
      check =
        let
          eval = evalDarwin [
            {
              config.substrate.modules.programs.shared.generic = {
                marker = "generic";
              };
              config.substrate.hosts.apple.system = "aarch64-darwin";
            }
          ];
          inherit ((captured eval)) modules;
        in
        builtins.elem eval.config.substrate.modules.programs.shared.generic modules;
    };

    # A module written for another class does not reach a darwin host. A NixOS
    # module would fail against nix-darwin, so silently including it would be
    # worse than not having the feature.
    nixosModulesDoNotReachADarwinHost = {
      check =
        let
          eval = evalDarwin [
            {
              config.substrate.settings.supportedClasses = [
                "darwin"
                "nixos"
              ];
              config.substrate.modules.programs.linuxOnly.nixos = {
                marker = "nixos";
              };
              config.substrate.hosts.apple.system = "aarch64-darwin";
            }
          ];
          inherit ((captured eval)) modules;
        in
        !(builtins.elem eval.config.substrate.modules.programs.linuxOnly.nixos modules);
    };

    # Contributions are how an extension reaches a class without the class
    # knowing it exists. This is the same path home-manager takes on a NixOS
    # host, and it is the only thing that makes Home Manager work on darwin.
    darwinContributionsAreLoaded = {
      check =
        let
          eval = evalDarwin [
            {
              config.substrate.settings.contributors = [
                {
                  class = "darwin";
                  contribute = _: [ { marker = "contributed"; } ];
                }
                {
                  class = "nixos";
                  contribute = _: [ { marker = "wrong-class"; } ];
                }
              ];
              config.substrate.hosts.apple.system = "aarch64-darwin";
            }
          ];
          inherit ((captured eval)) modules;
        in
        (builtins.filter (m: (m.marker or null) == "contributed") modules) == [
          {
            marker = "contributed";
          }
        ]
        && (builtins.filter (m: (m.marker or null) == "wrong-class") modules) == [ ];
    };

    # Extra module arguments reach darwin modules the same way they reach NixOS
    # ones -- this is `extraArgsGenerator`, not anything darwin-specific.
    extraArgsReachADarwinHost = {
      check =
        let
          eval = evalDarwin [
            {
              config.substrate.settings.extraArgsGenerators = [
                (_: {
                  marker = "arg";
                })
              ];
              config.substrate.hosts.apple.system = "aarch64-darwin";
            }
          ];
          inherit ((captured eval)) modules;
          argsModules = builtins.filter (m: m ? _module) modules;
        in
        builtins.length argsModules == 1 && (builtins.head argsModules)._module.args.marker == "arg";
    };

    # darwinModules is published through the same core mechanism as every other
    # key, so a consumer reads it the way it reads nixosModules.
    darwinModulesIsPublished = {
      check =
        let
          eval = evalDarwin [
            {
              config.substrate.publish.darwinModules.myModule = {
                marker = "published";
              };
            }
          ];
          publishers = eval.config.substrate.outputs.global.darwinModules;
        in
        builtins.length publishers == 1
        &&
          (builtins.head publishers).build { substrate = eval.config.substrate; }
          == eval.config.substrate.publish.darwinModules;
    };

    # The publish key is typed as a module, so something that is not one fails
    # here rather than reaching a consumer as a broken module set. The value is
    # forced deeply, because `attrsOf` checks its elements and an attrset is
    # already in whnf by the time tryEval looks at it.
    darwinModulesAreTyped = {
      check =
        let
          bad =
            (evalDarwin [ { config.substrate.publish.darwinModules.bad = 42; } ])
            .config.substrate.publish.darwinModules;
          result = builtins.tryEval (builtins.deepSeq bad bad);
        in
        !result.success;
    };
  };
in
runTests "Darwin Tests" tests
