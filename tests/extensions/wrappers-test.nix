# Tests for substrate wrappers extension
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib)
    lib
    runTests
    evalSubstrate
    ;
  inherit (lib.strings) hasInfix;

  # Minimal derivation stand-in: finalize post-processes via overrideAttrs,
  # and specs pass packages through types.package.
  mkFakeDrv =
    attrs:
    attrs
    // {
      outPath = attrs.outPath or "";
      isDerivation = true;
      override = f: mkFakeDrv (attrs // f);
      overrideAttrs = f: mkFakeDrv (attrs // (f attrs attrs));
    };

  fakePkg = mkFakeDrv {
    type = "derivation";
    pname = "foo";
    version = "1.0";
    outPath = "/nix/store/hash-foo-1.0";
    meta.mainProgram = "foo";
  };
  exe = lib.getExe fakePkg;

  fakePkgs = {
    secretspec = "/fake/secretspec";
    makeWrapper = "/fake/makeWrapper";
    makeBinaryWrapper = "/fake/makeBinaryWrapper";
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

  wrap = import ../../extensions/wrappers/wrap.nix {
    inherit lib;
    pkgs = fakePkgs;
  };
  inherit (wrap)
    toScript
    toOuter
    toStubFlags
    ;

  # real nixpkgs for pure derivation-existence checks (nothing is built)
  realWrap = import ../../extensions/wrappers/wrap.nix { inherit lib pkgs; };

  jqFake = mkFakeDrv { outPath = "/nix/store/hash-jq-1.7"; };

  throws = expr: !(builtins.tryEval (builtins.deepSeq expr expr)).success;
  joinLines = builtins.concatStringsSep "\n";

  eval = evalSubstrate [
    ../../extensions/wrappers/default.nix
    ../../extensions/secrets/default.nix
  ];

  argsFor =
    hostcfg:
    eval.config.substrate.lib.extraArgsGenerator {
      inherit hostcfg;
      usercfg = null;
      inputs = { };
      pkgs = fakePkgs;
    };

  hostArgs = argsFor { name = "unsouled"; };

  eggyEval = evalSubstrate [
    ../../extensions/wrappers/default.nix
    {
      config.substrate.settings.wrappers.backends.eggy = {
        options = {
          treat = lib.mkOption { type = lib.types.raw; };
        };
        build =
          { pkgs, ... }:
          cfg:
          mkFakeDrv {
            name = "eggy";
            treat = cfg.treat;
            package = cfg.package;
          };
      };
    }
  ];
  eggyArgs = eggyEval.config.substrate.lib.extraArgsGenerator {
    hostcfg = {
      name = "h";
    };
    usercfg = null;
    inputs = { };
    pkgs = fakePkgs;
  };

  mpvTyped = wrap.typed {
    backend = "script";
    options = {
      package = lib.mkOption {
        type = lib.types.package;
        default = fakePkg;
      };
      profile = lib.mkOption {
        type =
          with lib.types;
          enum [
            "fast"
            "hq"
          ];
        default = "fast";
      };
      extraSettings = lib.mkOption {
        type = with lib.types; attrsOf str;
        default = { };
      };
    };
    spec = config: {
      package = config.package;
      env.PROFILE = config.profile;
      files."p.conf".text = "x=1";
      args = [
        "--config"
        "p.conf"
      ];
    };
  };
in
runTests "Wrappers Extension Tests" {
  # --- pure text builders ---

  toScriptTextMode = {
    check =
      toScript {
        name = "ff";
        preHook = "echo p";
        env.A = "b c";
        runtimeInputs = [ jqFake ];
        cmd = "echo hi \"$\"";
      }
      == joinLines [
        "echo p"
        "export A='b c'"
        ''PATH="/nix/store/hash-jq-1.7/bin:$PATH"''
        "echo hi \"$\""
      ];
  };

  toScriptRejectsInvalidEnvName = {
    check = throws (toScript {
      name = "ff";
      cmd = "x";
      env."bad-key" = "x";
    });
  };

  toOuterSimple = {
    check = toOuter {
      binName = "foo";
      prefix = [ "uwsm app --" ];
    }
    == "exec -a \"$0\" uwsm app -- @out@/bin/.foo-core \"$@\"";
  };

  toOuterPostHookPropagatesExit = {
    check =
      builtins.elem "( exec -a \"$0\" @out@/bin/.foo-core \"$@\" )" (
        lib.splitString "\n" (toOuter {
          binName = "foo";
          postHook = "echo done";
        })
      )
      && hasInfix "code=$?" (toOuter {
        binName = "foo";
        postHook = "echo done";
      });
  };

  toStubFlagsTranslatesCfg = {
    check =
      toStubFlags {
        env.FOO = "bar baz";
        args = [ "--fixed" ];
        runtimeInputs = [ jqFake ];
        preHook = "echo hi";
      }
      == "--set FOO 'bar baz' --add-flags --fixed --prefix PATH : /nix/store/hash-jq-1.7/bin --run 'echo hi'";
  };

  # --- shell (in-place makeWrapper) pipeline ---

  shellStubInvocation = {
    check =
      let
        drv = wrap.withShell {
          package = fakePkg;
          env.FOO = "bar baz";
          args = [ "--flag=a" ];
          runtimeInputs = [ jqFake ];
          preHook = "echo hi";
        };
      in
      hasInfix ''wrapProgram "$out/bin/foo"'' drv.postBuild
      && hasInfix "--set FOO 'bar baz'" drv.postBuild
      && hasInfix ("--add-flags " + lib.escapeShellArg (lib.escapeShellArgs [ "--flag=a" ])) drv.postBuild
      && hasInfix "--prefix PATH : /nix/store/hash-jq-1.7/bin" drv.postBuild
      && hasInfix "--run 'echo hi'" drv.postBuild
      && drv.nativeBuildInputs == [ fakePkgs.makeWrapper ]
      && drv.paths == [ fakePkg ];
  };

  shellMetaAndName = {
    check =
      let
        drv = wrap { package = fakePkg; };
      in
      drv.name == "${lib.getName fakePkg}-wrapped" && drv.meta.mainProgram == "foo";
  };

  shellPatchesDesktopEntries = {
    check =
      let
        drv = wrap { package = fakePkg; };
      in
      hasInfix ''rm -rf "$out/share/applications"'' drv.postBuild
      && hasInfix ''sed "s|/nix/store/hash-foo-1.0|$out|g"'' drv.postBuild;
  };

  shellExeSelectsBinary = {
    check =
      hasInfix ''wrapProgram "$out/bin/helper"''
        (wrap {
          package = fakePkg;
          exe = "helper";
        }).postBuild;
  };

  shellFilesAndAliases = {
    check =
      let
        drv = wrap {
          package = fakePkg;
          files."mpv.conf".text = "vo=gpu";
          aliases = [ "foo2" ];
        };
      in
      hasInfix ''ln -s text:mpv.conf "$out/mpv.conf"'' drv.postBuild
      && hasInfix ''ln -s foo "$out/bin/foo2"'' drv.postBuild
      && drv.passthru.files."mpv.conf" == "text:mpv.conf";
  };

  shellPostBuildHookAppended = {
    check =
      hasInfix "rm $out/bin/sibling"
        (wrap {
          package = fakePkg;
          postBuildHook = "rm $out/bin/sibling";
        }).postBuild;
  };

  # capability mismatches are module errors or assertions
  shellRejectsPrefix = {
    check = throws (wrap {
      package = fakePkg;
      prefix = [ "uwsm app --" ];
    });
  };

  shellRejectsUnknownKeys = {
    check = throws (wrap {
      package = fakePkg;
      pkg = fakePkg;
    });
  };

  shellRequiresPackage = {
    check = throws (wrap {
      env.FOO = "bar";
    });
  };

  # --- passthru contract ---

  passthruMerged = {
    check =
      let
        drv = wrap {
          package = fakePkg;
          passthru.custom = "yes";
        };
      in
      drv.passthru.custom == "yes" && drv.passthru.wrapped.outPath == fakePkg.outPath;
  };

  passthruOverrideRebuilds = {
    check =
      let
        drv = wrap { package = fakePkg; };
        rebuilt = drv.passthru.override { version = "9.9"; };
      in
      # rerun rebuilds the whole pipeline around the overridden package
      rebuilt ? postBuild && rebuilt.passthru.wrapped.version == "9.9" && rebuilt.name == drv.name;
  };

  # --- binary pipeline ---

  binaryStubInvocation = {
    check =
      let
        drv = wrap.withBinary {
          package = fakePkg;
          env.FOO = "bar";
          args = [ "--t" ];
        };
      in
      hasInfix ''makeBinaryWrapper "$out/bin/foo"'' drv.postBuild
      && hasInfix "--set FOO bar" drv.postBuild
      && drv.name == "${lib.getName fakePkg}-wrapped-binary"
      && drv.nativeBuildInputs == [ fakePkgs.makeBinaryWrapper ];
  };

  # compiled stub runs no code, and it isn't even declared
  binaryRejectsPreHook = {
    check = throws (
      wrap.withBinary {
        package = fakePkg;
        preHook = "echo hi";
      }
    );
  };

  # --- script pipeline ---

  scriptPackageMode = {
    check =
      let
        drv = wrap.withScript { package = fakePkg; };
      in
      drv.name == "foo"
      && hasInfix ''makeWrapper ${exe} "$out/bin/foo"'' drv.body
      && hasInfix "--inherit-argv0" drv.body;
  };

  scriptLayeredPrefix = {
    check =
      let
        drv = wrap.withScript {
          package = fakePkg;
          prefix = [ "uwsm app --" ];
        };
      in
      hasInfix ''makeWrapper ${exe} "$out/bin/.foo-core"'' drv.body
      && hasInfix ''substitute script:exec -a "$0" uwsm app -- @out@/bin/.foo-core "$@" "$out/bin/foo"'' drv.body
      && hasInfix ''--replace-fail "@out@" "$out"'' drv.body;
  };

  scriptPostHookLayered = {
    check =
      let
        drv = wrap.withScript {
          package = fakePkg;
          postHook = "echo done";
        };
      in
      hasInfix ''"$out/bin/.foo-core" '' drv.body
      && hasInfix "exit $code" drv.body;
  };

  scriptTextMode = {
    check =
      let
        drv = wrap.withScript {
          name = "ff";
          cmd = "echo hi";
        };
      in
      drv.name == "ff" && hasInfix "echo hi" drv.body;
  };

  scriptRejectsPackageAndCmd = {
    check = throws (
      wrap.withScript {
        package = fakePkg;
        cmd = "x";
      }
    );
  };

  scriptTextModeRequiresName = {
    check = throws (wrap.withScript { cmd = "x"; });
  };

  scriptTextModeRejectsArgsAndPrefix = {
    check =
      throws (
        wrap.withScript {
          name = "ff";
          cmd = "x";
          args = [ "--nope" ];
        }
      )
      && throws (
        wrap.withScript {
          name = "ff";
          cmd = "x";
          prefix = [ "nope" ];
        }
      );
  };

  scriptFilesEnvFunctionSelfRef = {
    check =
      let
        drv = wrap.withScript {
          package = fakePkg;
          files."mpv.conf".text = "vo=gpu";
          env.MPV_CONFIG = f: f."mpv.conf";
          args = [
            "--config"
            "mpv.conf"
          ];
        };
      in
      hasInfix "--set MPV_CONFIG text:mpv.conf" drv.body && hasInfix ''ln -s text:mpv.conf "$out/mpv.conf"'' drv.body;
  };

  # --- wrap.typed ---

  typedEndToEnd = {
    check =
      let
        drv = mpvTyped { profile = "hq"; };
      in
      drv.name == "foo" && hasInfix "--set PROFILE hq" drv.body && hasInfix ''ln -s text:p.conf "$out/p.conf"'' drv.body;
  };

  typedDefaultsApply = {
    check = hasInfix "--set PROFILE fast" (mpvTyped { }).body;
  };

  typedRejectsUnknownSetting = {
    check = throws (mpvTyped {
      bogus = 1;
    });
  };

  typedValidatesKnobTypes = {
    check = throws (mpvTyped {
      profile = "nope";
    });
  };

  # the spec body flows through the same validated pipeline as plain specs
  typedSpecRejectsUnsupportedField = {
    check = throws (
      wrap.typed {
        backend = "shell";
        options = { };
        spec = c: {
          package = fakePkg;
          prefix = [ "nope" ];
        };
      } { }
    );
  };

  typedOptionsEmbedIntoNixpkgsModule = {
    check =
      let
        embedded = lib.evalModules {
          modules = [
            ({ options, lib, ... }: {
              options.mypv = lib.mkOption {
                type = lib.types.submodule mpvTyped.options;
                default = { };
              };
            })
            { config.mypv.profile = "hq"; }
          ];
        };
        drv = mpvTyped embedded.config.mypv;
      in
      hasInfix "--set PROFILE hq" drv.body;
  };

  # --- wiring and registry ---

  wrapArrivesAsModuleArg = {
    check =
      hostArgs ? wrap
      && (hostArgs.wrap { package = fakePkg; }) ? postBuild
      && (hostArgs.wrap.withScript { package = fakePkg; }).name == "foo"
      && (hostArgs.wrap.withShell { package = fakePkg; }) ? postBuild;
  };

  contributedBackendAppearsAsWrapName = {
    check =
      let
        drv = eggyArgs.wrap.withEggy {
          package = fakePkg;
          treat = "cup";
        };
      in
      drv.treat == "cup" && drv.package == fakePkg;
  };

  contributedBackendValidatesKeys = {
    check = throws (
      eggyArgs.wrap.withEggy {
        package = fakePkg;
        bogus = "x";
      }
    );
  };

  contributedBackendsAbsentWithoutContributors = {
    check = !(hostArgs.wrap ? withBubblewrap) && !(hostArgs.wrap ? withEggy);
  };

  defaultBackendSwitchesFunctor = {
    check =
      let
        binEval = evalSubstrate [
          ../../extensions/wrappers/default.nix
          { config.substrate.settings.wrappers.defaultBackend = "binary"; }
        ];
        binArgs = binEval.config.substrate.lib.extraArgsGenerator {
          hostcfg = {
            name = "h";
          };
          usercfg = null;
          inputs = { };
          pkgs = fakePkgs;
        };
      in
      # functor follows the configured default...
      (binArgs.wrap { package = fakePkg; }).name == "${lib.getName fakePkg}-wrapped-binary"
      # ...and its option language changes with it
      && throws (
        binArgs.wrap {
          package = fakePkg;
          preHook = "echo hi";
        }
      )
      # named callables are unaffected by the default
      && (binArgs.wrap.withShell {
        package = fakePkg;
        preHook = "echo hi";
      })
        ? postBuild;
  };

  defaultBackendMustNameKnownBackend = {
    check =
      throws
        (
          (evalSubstrate [
            ../../extensions/wrappers/default.nix
            { config.substrate.settings.wrappers.defaultBackend = "bogus"; }
          ]).config.substrate.lib.extraArgsGenerator
            {
              hostcfg = {
                name = "h";
              };
              usercfg = null;
              inputs = { };
              pkgs = fakePkgs;
            }
        ).wrap;
  };

  typedWithoutBackendFollowsDefault = {
    check =
      let
        binEval = evalSubstrate [
          ../../extensions/wrappers/default.nix
          { config.substrate.settings.wrappers.defaultBackend = "binary"; }
        ];
        w = binEval.config.substrate.lib.extraArgsGenerator {
          hostcfg = {
            name = "h";
          };
          usercfg = null;
          inputs = { };
          pkgs = fakePkgs;
        };
        wrap = w.wrap;
        d = wrap.typed {
          options = { };
          spec = c: { package = fakePkg; };
        };
      in
      (d { }).name == "${lib.getName fakePkg}-wrapped-binary";
  };

  reservedBackendNamesRejected = {
    check =
      throws
        (
          (evalSubstrate [
            ../../extensions/wrappers/default.nix
            {
              config.substrate.settings.wrappers.backends.shell = {
                build = { pkgs, ... }: cfg: cfg.package;
              };
            }
          ]).config.substrate.lib.extraArgsGenerator
            {
              hostcfg = {
                name = "h";
              };
              usercfg = null;
              inputs = { };
              pkgs = fakePkgs;
            }
        ).wrap;
  };

  # --- real-nixpkgs integration (pure eval, nothing built) ---

  realDerivationsProducePaths = {
    check =
      let
        inner = realWrap.withScript {
          package = pkgs.hello;
          aliases = [ "hi" ];
        };
        outer = realWrap.withScript {
          package = inner;
          env.GREET = "nested";
        };
        inplaced = realWrap.withShell { package = pkgs.hello; };
      in
      lib.isString inner.outPath
      && lib.isString outer.outPath
      && outer.passthru.wrapped.outPath == inner.outPath
      && inplaced.meta.mainProgram == "hello"
      && (builtins.tryEval (realWrap { })).success == false;
  };

  # Integration: secrets prefixes compose into standalone wrapper exec lines.
  secretsPrefixComposesIntoScriptWrapper = {
    check =
      let
        drv = hostArgs.wrap.withScript {
          package = fakePkg;
          prefix = [
            (hostArgs.secrets.prefix { scope = "github-mcp"; })
          ];
        };
      in
      hasInfix ''makeWrapper ${exe} "$out/bin/.foo-core"'' drv.body
      && hasInfix "exec -a \"$0\" /fake/secretspec/bin/secretspec run --file /etc/secretspec.toml --scope github-mcp" drv.body
      && hasInfix ''-- @out@/bin/.foo-core "$@"'' drv.body;
  };
}
