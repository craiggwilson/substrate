# Tests for substrate bubblewrap extension
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
  inherit (lib.strings) hasInfix;

  mkFakeDrv =
    attrs:
    attrs
    // {
      # type is what lib.isDerivation reads, so a fake has to carry it for
      # anything that takes the result as a package.
      type = attrs.type or "derivation";
      outPath = attrs.outPath or "";
      isDerivation = true;
      override = f: mkFakeDrv (attrs // f);
      overrideAttrs = f: mkFakeDrv (attrs // (f attrs attrs));
    };

  fakeJailNix = {
    outPath = pkgs.path;
    lib = {
      init = _p: throw "bubblewrap extension should call extend, not init";
      extend = args: {
        pkgsTag = args.pkgs.tag or null;
        basePermissions = args.basePermissions or null;
        additionalCombinators = args.additionalCombinators or null;
        # The combinators the contributor translates the core vocabulary into.
        # Each returns a marker that ends up in the fake jail's name, so a test
        # can see what the wrapper asked for. Markers stay alphanumeric: that name
        # becomes part of a store path, and punctuation does not survive that.
        combinators = {
          set-env = n: v: "setenv${n}${v}";
          add-pkg-deps = pkgs': "pathdeps${toString (builtins.length pkgs')}";
          bind-pkg = path: _pkg: "bindpath${builtins.replaceStrings [ "/" "." ":" ] [ "_" "_" "_" ] path}";
          try-fwd-env = n: "fwd${n}";
        };
        # real jail.nix returns a callable: `jail name executable permissions`.
        # The jail is what a bubblewrap wrapper wraps, so it carries what it was
        # asked for in its store path — that is where a test can see it.
        __functor =
          _self: name: exe: perms:
          mkFakeDrv {
            jailName = name;
            executable = toString exe;
            permsTag = if lib.isList perms then lib.concatStringsSep "," perms else "fn";
            outPath = "/nix/store/hash-jail-${name}-${
              if lib.isList perms then lib.concatStringsSep "," perms else "fn"
            }";
            # A real jail is a derivation, so the wrapper can name its output
            # after what it wraps.
            name = "${name}-jailed";
            meta.mainProgram = name;
          };
      };
    };
  };

  fakePkgs = {
    tag = "host-pkgs";
    makeWrapper = "/fake/makeWrapper";
    makeBinaryWrapper = "/fake/makeBinaryWrapper";
    writeShellScriptBin = name: _text: "drv:${name}";
    writeShellScript = _name: text: "script:${text}";
    writeText = name: _text: "text:${name}";
    # symlinkJoin is how every wrapper is built now, so `body` is the postBuild
    # script: the tests read the build script, not which builder took it.
    symlinkJoin = a: mkFakeDrv (a // { body = a.postBuild or ""; });
    runCommand =
      name: args: body:
      mkFakeDrv (
        args
        // {
          inherit name body;
        }
      );
  };

  fakeOpPkg = mkFakeDrv { outPath = "/nix/store/hash-op"; };

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
        inputs = { };
        coreInputs = {
          jail-nix = fakeJailNix;
        };
      };
    };

  bubblewrapModules = [ ../../extensions/bubblewrap/default.nix ];

  eval = evalWith bubblewrapModules;

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

  wrapsEval = evalWith (bubblewrapModules ++ [ ../../extensions/wrappers/default.nix ]);

  # `wrap` reaches a target configuration through a class module, so it is
  # exercised the way a module of that configuration uses it rather than through
  # the generator. pkgs flows in via the contribution context, so the wrapper is
  # built with the fake package set.
  wrapIn =
    spec:
    testLib.classWrap {
      eval = wrapsEval;
      inherit spec;
      context = {
        pkgs = fakePkgs;
        coreInputs = {
          jail-nix = fakeJailNix;
        };
      };
    };
  wrapsArgs = {
    wrap = wrapIn;
  };

  # A contributor that introduces an environment variable and does nothing else,
  # standing in for one that resolves a secret at exec time.
  forwarderArgs = {
    wrap =
      spec:
      testLib.classWrap {
        eval = evalWith (
          bubblewrapModules
          ++ [
            ../../extensions/wrappers/default.nix
            {
              config.substrate.settings.wrappers.contributors.token = {
                priority = 3;
                options = { };
                envNames = _ctx: _spec: [ "TOKEN" ];
              };
            }
          ]
        );
        inherit spec;
        context = {
          pkgs = fakePkgs;
          coreInputs = {
            jail-nix = fakeJailNix;
          };
        };
      };
  };

  # integration against the real jail.nix (flake input); bubblewrap is
  # linux-only, so the assertions short-circuit elsewhere
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  realTest = check: jailNix == null || !isLinux || check;

  realEval = lib.evalModules {
    modules = testLib.coreModules ++ bubblewrapModules ++ [ ../../extensions/wrappers/default.nix ];
    specialArgs = {
      inputs = { };
      coreInputs = {
        jail-nix = jailNix;
      };
    };
  };
  # jailLib is still a generator arg (it needs only pkgs); wrap is not, so the
  # two are reached by different paths.
  realArgs = realEval.config.substrate.lib.extraArgsGenerator {
    hostcfg = {
      name = "h";
    };
    usercfg = null;
    inputs = { };
    inherit pkgs;
  };
  realWrap =
    spec:
    testLib.classWrap {
      eval = realEval;
      inherit spec;
      context = {
        inherit pkgs;
        coreInputs = {
          jail-nix = jailNix;
        };
      };
    };

  throws = expr: !(builtins.tryEval (builtins.deepSeq expr expr)).success;
in
runTests "Bubblewrap Extension Tests" {
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
          bubblewrapModules
          ++ [
            {
              config.substrate.settings.bubblewrap.basePermissions = _c: [ "base" ];
              config.substrate.settings.bubblewrap.additionalCombinators = _c: {
                mine = "x";
              };
            }
          ]
        );
        lib_ = (moduleArgs e).jailLib;
      in
      lib_.basePermissions != null && lib_.additionalCombinators != null;
  };

  # without the wrappers extension, no backend option exists and bubblewrap still loads
  bubblewrapWorksWithoutWrappers = {
    check = !(eval.config.substrate.settings ? wrappers);
  };

  # with wrappers loaded, bubblewrap joins in as a contributor: it contributes
  # the program to wrap, so the jail is what the wrapper runs.
  bubblewrapContributorRegistered = {
    check = wrapsEval.config.substrate.settings.wrappers.contributors ? bubblewrap;
  };

  bubblewrapContributesTheProgram = {
    check =
      let
        drv = wrapsArgs.wrap {
          package = fakeDrv;
          bubblewrap.permissions = [ "net" ];
        };
      in
      # The jail is what the wrapper runs, not the package: with nothing for a
      # core to carry, the stub execs the jail directly.
      hasInfix "exec -a \"$0\"" drv.body
      && hasInfix "/nix/store/hash-jail-foo-isolated-net/bin/foo-isolated" drv.body
      && !(hasInfix "hash-foo-1.0/bin/foo" drv.body)
      # and the wrapper still reports the package the caller asked for
      && drv.passthru.wrapped.outPath == fakeDrv.outPath;
  };

  bubblewrapCustomName = {
    check =
      let
        drv = wrapsArgs.wrap {
          package = fakeDrv;
          name = "browser";
          bubblewrap.permissions = [
            "gpu"
            "net"
          ];
        };
      in
      # `name` renames the wrapper, and the jail is named after it.
      # `name` renames the wrapper's own executable; the jail is named after it,
      # and the output's mainProgram is the new name.
      hasInfix "/nix/store/hash-jail-browser-gpu,net/bin/browser" drv.body
      && hasInfix ''mv -f "$out/bin/.browser-outer" "$out/bin/browser"'' drv.body
      && drv.meta.mainProgram == "browser";
  };

  bubblewrapPassesCombinatorFunction = {
    check =
      hasInfix "/nix/store/hash-jail-foo-isolated-fn/bin/foo-isolated"
        (wrapsArgs.wrap {
          package = fakeDrv;
          bubblewrap.permissions = _c: [ "fn" ];
        }).body;
  };

  # Permissions are the contributor's own options; the wrapper language belongs to
  # the spec, so a field under the contributor's key is an error.
  bubblewrapRejectsUnknownKeys = {
    check = throws (
      wrapsArgs.wrap {
        package = fakeDrv;
        bubblewrap.env.NOPE = "x";
      }
    );
  };

  bubblewrapRejectsMissingPackage = {
    check = throws (
      wrapsArgs.wrap {
        bubblewrap.permissions = [ ];
      }
    );
  };

  # The core vocabulary reaches the jail rather than being dropped: jail.nix's
  # base permissions clear the environment, so env becomes --setenv and
  # runtimeInputs become PATH entries with their closures bound.
  bubblewrapTranslatesTheCoreVocabulary = {
    check =
      let
        drv = wrapsArgs.wrap {
          package = fakeDrv;
          env.GREET = "hi";
          runtimeInputs = [ fakeOpPkg ];
          bubblewrap.permissions = [ ];
        };
      in
      hasInfix "setenvGREEThi" drv.body && hasInfix "pathdeps1" drv.body;
  };

  # Files are bound at the store paths the spec resolved them to, so an env value
  # computed from a file still points at the right thing inside.
  bubblewrapBindsFilesAtTheirOwnPaths = {
    check =
      hasInfix "bindpathtext_mpv_conf"
        (wrapsArgs.wrap {
          package = fakeDrv;
          files."mpv.conf".text = "vo=gpu";
          bubblewrap.permissions = [ ];
        }).body;
  };

  # A name another contributor advertised is forwarded by value, so a resolved
  # secret reaches the jailed program without appearing in the bwrap arguments.
  bubblewrapForwardsAdvertisedEnvNames = {
    check =
      let
        drv = forwarderArgs.wrap {
          package = fakeDrv;
          env.GREET = "hi";
          token = { };
          bubblewrap.permissions = [ ];
        };
      in
      hasInfix "fwdTOKEN" drv.body
      # the wrapper's own env is set literally instead, so forwarding it is moot
      && !(hasInfix "fwdGREET" drv.body);
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
      lib.isDerivation (realWrap {
        package = pkgs.hello;
        name = "jail-test-real";
        bubblewrap.permissions = c: with c; [ base ];
      })
    );
  };

  # The wrapper wraps the jail: its build refers to the jail launcher, not to
  # hello, so there is no path from the wrapper straight to the program.
  realBubblewrapJailsTheEntry = {
    check = realTest (
      let
        wrapped = realWrap {
          package = pkgs.hello;
          bubblewrap.permissions = c: with c; [ base ];
        };
      in
      lib.isDerivation wrapped
      && lib.strings.hasInfix "-isolated" wrapped.buildCommand
      # and it still reports the package the caller asked for
      && wrapped.passthru.wrapped == pkgs.hello
    );
  };

  realBubblewrapRejectsUnknownKeys = {
    check = realTest (
      throws (realWrap {
        package = pkgs.hello;
        bubblewrap.env.NOPE = "x";
      })
    );
  };
}
