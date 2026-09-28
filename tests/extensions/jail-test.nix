# Tests for substrate jail extension
{
  pkgs ? import <nixpkgs> { },
  jailNix ? null,
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib)
    lib
    runTests
    ;

  mkFakeDrv =
    attrs:
    attrs
    // {
      outPath = attrs.outPath or "";
      isDerivation = true;
      override = f: mkFakeDrv (attrs // f);
      overrideAttrs = f: mkFakeDrv (attrs // (f attrs attrs));
    };

  fakeJailNix = {
    lib = {
      init = p: throw "jail extension should call extend, not init";
      extend = args: {
        pkgsTag = args.pkgs.tag or null;
        basePermissions = args.basePermissions or null;
        additionalCombinators = args.additionalCombinators or null;
        combinators = { };
        # real jail.nix returns a callable: `jail name executable permissions`
        __functor =
          self: name: exe: perms:
          mkFakeDrv {
            jailName = name;
            executable = toString exe;
            permsTag = if lib.isList perms then lib.concatStringsSep "," perms else "fn";
          };
      };
    };
  };

  fakePkgs = {
    tag = "host-pkgs";
    makeWrapper = "/fake/makeWrapper";
    makeBinaryWrapper = "/fake/makeBinaryWrapper";
    writeShellScriptBin = name: text: "drv:${name}";
    writeShellScript = name: text: "script:${text}";
    writeText = name: text: "text:${name}";
    symlinkJoin = a: mkFakeDrv a;
    runCommand =
      name: args: body:
      mkFakeDrv (
        args
        // {
          inherit name body;
        }
      );
  };

  fakeDrv = mkFakeDrv {
    type = "derivation";
    pname = "foo";
    version = "1.0";
    outPath = "/nix/store/hash-foo-1.0";
    meta.mainProgram = "foo";
  };

  evalWith =
    modules:
    lib.evalModules {
      modules = testLib.coreModules ++ modules;
      specialArgs = {
        inputs = {
          jail-nix = fakeJailNix;
        };
      };
    };

  jailModules = [ ../../extensions/jail/default.nix ];

  eval = evalWith jailModules;

  moduleArgs =
    e:
    e.config.substrate.lib.extraArgsGenerator {
      hostcfg = {
        name = "h";
      };
      usercfg = null;
      inputs = { };
      pkgs = fakePkgs;
    };

  wrapsEval = evalWith (jailModules ++ [ ../../extensions/wrappers/default.nix ]);
  wrapsArgs = moduleArgs wrapsEval;

  # integration against the real jail.nix (flake input); bubblewrap is
  # linux-only, so the assertions short-circuit elsewhere
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  realTest = check: jailNix == null || !isLinux || check;

  realEval = lib.evalModules {
    modules = testLib.coreModules ++ jailModules ++ [ ../../extensions/wrappers/default.nix ];
    specialArgs = {
      inputs = {
        jail-nix = jailNix;
      };
    };
  };
  realArgs = realEval.config.substrate.lib.extraArgsGenerator {
    hostcfg = {
      name = "h";
    };
    usercfg = null;
    inputs = { };
    pkgs = pkgs;
  };

  throws = expr: !(builtins.tryEval (builtins.deepSeq expr expr)).success;
in
runTests "Jail Extension Tests" {
  # jailLib extraArg: pkgs-bound jail.nix callable
  jailLibIsPkgsBound = {
    check = (moduleArgs eval).jailLib.pkgsTag == "host-pkgs";
  };

  rawJailArgRemoved = {
    check = !(moduleArgs eval) ? jail;
  };

  basePermissionsForwardedToJailNix = {
    check =
      let
        e = evalWith (
          jailModules
          ++ [
            {
              config.substrate.settings.jail.basePermissions = c: [ "base" ];
              config.substrate.settings.jail.additionalCombinators = c: {
                mine = "x";
              };
            }
          ]
        );
        lib_ = (moduleArgs e).jailLib;
      in
      lib_.basePermissions != null && lib_.additionalCombinators != null;
  };

  # without the wrappers extension, no backend option exists and jail still loads
  jailWorksWithoutWrappers = {
    check = !(eval.config.substrate.settings ? wrappers);
  };

  # with wrappers loaded, wrap.withBubblewrap is registered and composes
  bubblewrapBackendRegistered = {
    check =
      wrapsArgs.wrap ? withBubblewrap
      &&
        (wrapsArgs.wrap.withBubblewrap {
          package = fakeDrv;
          permissions = [ "net" ];
        }).jailName == "foo-isolated";
  };

  bubblewrapCustomName = {
    check =
      (wrapsArgs.wrap.withBubblewrap {
        package = fakeDrv;
        name = "browser";
        permissions = [
          "gpu"
          "net"
        ];
      }).permsTag == "gpu,net";
  };

  bubblewrapPassesCombinatorFunction = {
    check =
      (wrapsArgs.wrap.withBubblewrap {
        package = fakeDrv;
        permissions = c: [ "fn" ];
      }).permsTag == "fn";
  };

  bubblewrapRejectsUnknownKeys = {
    check = throws (
      wrapsArgs.wrap.withBubblewrap {
        package = fakeDrv;
        env.NOPE = "x";
      }
    );
  };

  bubblewrapRejectsMissingPackage = {
    check = throws (
      wrapsArgs.wrap.withBubblewrap {
        permissions = [ ];
      }
    );
  };

  # --- real jail.nix input (skipped when the flake input is absent) ---

  realJailLibShape = {
    check = realTest (
      let
        j = realArgs.jailLib;
      in
      j ? __functor && j.combinators ? base && j.combinators ? readonly
    );
  };

  realBubblewrapProducesDerivation = {
    check = realTest (
      lib.isDerivation (
        realArgs.wrap.withBubblewrap {
          package = pkgs.hello;
          name = "jail-test-real";
          permissions = c: with c; [ base ];
        }
      )
    );
  };

  realBubblewrapDefaultName = {
    check = realTest (
      lib.strings.hasInfix "-isolated" (
        toString (
          realArgs.wrap.withBubblewrap {
            package = pkgs.hello;
            permissions = [ ];
          }
        )
      )
    );
  };

  realBubblewrapRejectsUnknownKeys = {
    check = realTest (
      throws (
        realArgs.wrap.withBubblewrap {
          package = pkgs.hello;
          env.NOPE = "x";
        }
      )
    );
  };
}
