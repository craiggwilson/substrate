# Tests for substrate includes extension
# Run with: nix eval -f substrate/tests/extensions/includes-test.nix
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib mkEvalSubstrate runTests;

  evalSubstrate = mkEvalSubstrate [
    ../../core/settings.nix
    ../../core/lib.nix
    ../../core/modules.nix
    ../../core/finders.nix
    ../../core/hosts.nix
    ../../core/users.nix
    ../../core/outputs.nix
    ../../core/overlays.nix
    ../../core/checks.nix
    ../../extensions/nixos/default.nix
    ../../extensions/includes/default.nix
  ];

  # A tree of three modules, each reachable in more than one way:
  #   desktop -> gui (a plain path)
  #   desktop -> devices, only for a host whose name is "workstation"
  nixpkgsClass = {
    config.substrate.settings.supportedClasses = [ "nixos" ];
  };

  # Paths of the modules a finder was handed, which is also the order it returns
  # them in. `find` must hand back modules, so this reads __path off each.
  pathsOf =
    eval: cfgs:
    builtins.map (node: node.__path) (eval.config.substrate.moduleFinders.by-includes.find cfgs);

  # Whether evaluating a finder result blows up.
  fails = thunk: !(builtins.tryEval (builtins.deepSeq thunk true)).success;

  tests = {
    # -- naming modules ------------------------------------------------------

    hostIncludesModuleClosure = {
      check =
        let
          eval = evalSubstrate [
            nixpkgsClass
            {
              config.substrate.hosts.workstation.includes = [ "desktop" ];
              config.substrate.modules.desktop = {
                includes = [ "gui" ];
                nixos = { };
              };
              config.substrate.modules.gui.nixos = { };
            }
          ];
        in
        lib.length (pathsOf eval [ eval.config.substrate.hosts.workstation ]) == 2;
    };

    moduleIncludesTransitively = {
      check =
        let
          eval = evalSubstrate [
            nixpkgsClass
            {
              config.substrate.hosts.workstation.includes = [ "desktop" ];
              config.substrate.modules.desktop = {
                includes = [ "gui" ];
                nixos = { };
              };
              config.substrate.modules.gui = {
                includes = [ "wayland" ];
                nixos = { };
              };
              config.substrate.modules.wayland.nixos = { };
            }
          ];
        in
        lib.length (pathsOf eval [ eval.config.substrate.hosts.workstation ]) == 3;
    };

    # A function can return a list of strings and/or references.
    functionReturnsAListOfModuleNames = {
      check =
        let
          eval = evalSubstrate [
            nixpkgsClass
            ({ config, ... }: {
              substrate.hosts.workstation.includes = [
                "desktop"
                config.substrate.modules.gui
              ];
              substrate.modules.desktop.nixos = { };
              substrate.modules.gui.nixos = { };
            })
          ];
        in
        pathsOf eval [ eval.config.substrate.hosts.workstation ] == [
          "desktop"
          "gui"
        ];
    };

    listAndFunctionAgree = {
      check =
        let
          eval = evalSubstrate [
            nixpkgsClass
            ({ config, ... }: {
              substrate.hosts.byPath.includes = [ "desktop" ];
              substrate.hosts.byNode.includes = [ config.substrate.modules.desktop ];
              substrate.hosts.byFunction.includes = _: [ "desktop" ];
              substrate.modules.desktop.nixos = { };
            })
          ];
          found = host: pathsOf eval [ eval.config.substrate.hosts.${host} ];
        in
        found "byPath" == found "byNode" && found "byNode" == found "byFunction";
    };

    # Two modules contributing to one `includes` must both be honoured, and a
    # definition written as a function must still be read as a function once
    # another definition has turned the value into a list.
    # `lib.optionals` produces [] or a value, and both have to be understood.
    optionalsIncludeOnlyWhenTrue = {
      check =
        let
          mk =
            laptop:
            evalSubstrate [
              nixpkgsClass
              (_: {
                substrate.hosts.workstation.name = if laptop then "workstation" else "laptop";
                substrate.hosts.workstation.includes =
                  { hostcfg, ... }: lib.optionals (hostcfg.name == "workstation") [ "desktop" ];
                substrate.modules.desktop.nixos = { };
              })
            ];
          found = laptop: pathsOf (mk laptop) [ (mk laptop).config.substrate.hosts.workstation ];
        in
        found true == [ "desktop" ] && found false == [ ];
    };

    # A function is handed the context, and position decides: the config find
    # was handed first is the host, so it is the one whose usercfg is null.
    contextFunctionSeesTheHost = {
      check =
        let
          eval = evalSubstrate [
            nixpkgsClass
            (_: {
              substrate.hosts.workstation.name = "workstation";
              substrate.hosts.workstation.includes =
                { usercfg, ... }: if usercfg == null then [ "desktop" ] else [ ];
              substrate.modules.desktop.nixos = { };
            })
          ];
        in
        pathsOf eval [ eval.config.substrate.hosts.workstation ] == [ "desktop" ];
    };

    contextFunctionSeesTheUser = {
      check =
        let
          eval = evalSubstrate [
            nixpkgsClass
            (_: {
              substrate.users.alice = { };
              substrate.users.alice.includes =
                { usercfg, ... }: if usercfg != null && usercfg.name == "alice" then [ "desktop" ] else [ ];
              substrate.modules.desktop.nixos = { };
              substrate.hosts.workstation = { };
            })
          ];
          s = eval.config.substrate;
        in
        # A lone config is always the host, so a user is only ever the second
        # config: find is handed the host and the user it is being built for.
        pathsOf eval [
          s.hosts.workstation
          s.users.alice
        ] == [ "desktop" ]
        && pathsOf eval [ s.users.alice ] == [ ];
    };

    # -- failures ------------------------------------------------------------

    # Regression: find used to hand back { path, node } records, which every
    # consumer reads as a module and finds no class content in.
    findReturnsModulesNotEntries = {
      check =
        let
          eval = evalSubstrate [
            nixpkgsClass
            {
              config.substrate.hosts.workstation.includes = [ "desktop" ];
              config.substrate.modules.desktop.nixos = { };
            }
          ];
          found = eval.config.substrate.moduleFinders.by-includes.find [
            eval.config.substrate.hosts.workstation
          ];
        in
        lib.all (node: node ? nixos) found;
    };

    # The path a builder actually takes, and the one that used to return nothing
    # at all. The closure is evaluated rather than counted, so a finder handing
    # back records instead of modules shows up here as a missing option.
    findModulesForClassEvaluatesTheClosure = {
      check =
        let
          eval = evalSubstrate [
            nixpkgsClass
            {
              config.substrate.hosts.workstation.includes = [ "desktop" ];
              config.substrate.modules.desktop = {
                includes = [ "gui" ];
                nixos = {
                  desktop = true;
                };
              };
              config.substrate.modules.gui.nixos = {
                gui = true;
              };
              config.substrate.modules.never.nixos = {
                never = true;
              };
            }
          ];
          s = eval.config.substrate;
          # The class content is a module, so it has to land in a configuration
          # that declares what it sets. Declaring one option per module makes the
          # assertion about the merged result rather than about a count.
          flag =
            _:
            lib.mkOption {
              type = lib.types.bool;
              default = false;
            };
          built = lib.evalModules {
            modules = [
              {
                options = {
                  desktop = flag "desktop";
                  gui = flag "gui";
                  never = flag "never";
                };
              }
            ]
            ++ s.lib.findModulesForClass "nixos" [ s.hosts.workstation ];
          };
        in
        built.config.desktop && built.config.gui && !built.config.never;
    };

    genericModulesComeAlongToo = {
      check =
        let
          eval = evalSubstrate [
            nixpkgsClass
            {
              config.substrate.hosts.workstation.includes = [ "desktop" ];
              config.substrate.modules.desktop = {
                nixos = { };
                generic = { };
              };
            }
          ];
          s = eval.config.substrate;
        in
        lib.length (s.lib.findModulesForClass "nixos" [ s.hosts.workstation ]) == 2;
    };

    # -- laziness ------------------------------------------------------------

    # An entry must not be evaluated when the option is read, only when the walk
    # reaches it. A shallow option type is what makes that true: lib.types.listOf
    # checks every element, which would follow each named subtree to look at it.
    entriesAreNotForcedByReadingTheOption = {
      check =
        let
          eval = evalSubstrate [
            nixpkgsClass
            ({ config, ... }: {
              substrate.hosts.workstation.includes = [
                config.substrate.modules.desktop
                (throw "an includes entry was forced before the walk reached it")
              ];
              substrate.modules.desktop.nixos = { };
            })
          ];
          includes = eval.config.substrate.hosts.workstation.includes;
        in
        lib.isAttrs (builtins.head includes);
    };

    # -- failures ------------------------------------------------------------

    missingModulePathFails = {
      check =
        let
          eval = evalSubstrate [
            nixpkgsClass
            {
              config.substrate.hosts.workstation.includes = [ "missing" ];
              config.substrate.modules.desktop.nixos = { };
            }
          ];
        in
        fails (
          eval.config.substrate.moduleFinders.by-includes.find [
            eval.config.substrate.hosts.workstation
          ]
        );
    };

    cycleFails = {
      check =
        let
          eval = evalSubstrate [
            nixpkgsClass
            {
              config.substrate.hosts.workstation.includes = [ "desktop" ];
              config.substrate.modules.desktop = {
                includes = [ "gui" ];
                nixos = { };
              };
              config.substrate.modules.gui = {
                includes = [ "desktop" ];
                nixos = { };
              };
            }
          ];
        in
        fails (
          eval.config.substrate.moduleFinders.by-includes.find [
            eval.config.substrate.hosts.workstation
          ]
        );
    };

    namingAHostConfigFails = {
      check =
        let
          eval = evalSubstrate [
            nixpkgsClass
            ({ config, ... }: {
              substrate.hosts.workstation.includes = [ config.substrate.hosts.workstation ];
              substrate.modules.desktop.nixos = { };
            })
          ];
        in
        fails (
          eval.config.substrate.moduleFinders.by-includes.find [
            eval.config.substrate.hosts.workstation
          ]
        );
    };

    namingSomethingElseEntirelyFails = {
      check =
        let
          eval = evalSubstrate [
            nixpkgsClass
            {
              config.substrate.hosts.workstation.includes = [ 42 ];
              config.substrate.modules.desktop.nixos = { };
            }
          ];
        in
        fails (
          eval.config.substrate.moduleFinders.by-includes.find [
            eval.config.substrate.hosts.workstation
          ]
        );
    };

  };
in
runTests "Includes Tests" tests
