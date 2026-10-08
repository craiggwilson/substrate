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
      # type = "derivation" by default so a wrapper result can itself be passed
      # as another wrapper's package (types.package checks it).
      type = attrs.type or "derivation";
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

  # What the shared render writes for a `secretspec` configuration under the fake
  # pkgs, and therefore what a wrapper in that configuration reads.
  fakeStoreManifest = "text:secretspec.toml";

  fakePkgs = {
    secretspec = "/fake/secretspec";
    makeWrapper = "/fake/makeWrapper";
    makeBinaryWrapper = "/fake/makeBinaryWrapper";
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

  wrap = import ../../extensions/wrappers/wrap.nix {
    inherit lib;
    pkgs = fakePkgs;
  };
  wrapPackage = wrap.package;

  # The pure text builders a wrapper renders with, under test directly.
  common = import ../../extensions/wrappers/common.nix {
    inherit lib;
    pkgs = fakePkgs;
  };
  render = import ../../extensions/wrappers/render.nix {
    inherit lib pkgs common;
  };
  inherit (render)
    binaryFlags
    coreFlags
    needsCore
    toOuter
    ;

  # real nixpkgs for pure derivation-existence checks (nothing is built)
  realWrap = (import ../../extensions/wrappers/wrap.nix { inherit lib pkgs; }).package;

  jqFake = mkFakeDrv { outPath = "/nix/store/hash-jq-1.7"; };
  opFake = mkFakeDrv { outPath = "/nix/store/hash-op-2.32.0"; };

  throws = expr: !(builtins.tryEval (builtins.deepSeq expr expr)).success;

  # The stub text of a standalone wrapper, as the build embeds it.
  stubText =
    drv:
    lib.removePrefix "substitute script:" (
      lib.head (lib.filter (line: hasInfix "substitute script:" line) (lib.splitString "\n" drv.body))
    );

  # A fully assembled spec: the pure builders render one, so they are handed one
  # here. Pinning the fields also pins what the core assembles for them.
  specOf =
    fields:
    {
      aliases = [ ];
      args = [ ];
      binName = "foo";
      chain = [ ];
      env = { };
      exe = null;
      extraRuntimeInputs = [ ];
      files = { };
      forwarded = [ ];
      name = null;
      package = fakePkg;
      postHook = "";
      preHook = "";
      prefix = [ ];
      program = fakePkg;
      runtimeInputs = [ ];
      setup = "";
      stub = "makeWrapper";
    }
    // fields;

  # A target configuration carrying the secrets extension. Its class module is
  # contributed into the same module system as wrappers', so it declares the real
  # secretspec options and this supplies the values plus the NixOS options that
  # module also configures. A wrapper reads config.secretspec from here.
  secretsTarget = {
    options.networking.hostName = lib.mkOption {
      type = lib.types.str;
      default = "h";
    };
    options.environment.systemPackages = lib.mkOption {
      type = lib.types.listOf lib.types.raw;
      default = [ ];
    };
    options.systemd.services = lib.mkOption {
      type = lib.types.attrsOf lib.types.raw;
      default = { };
    };
    options.systemd.tmpfiles = lib.mkOption {
      type = lib.types.submodule (_: {
        options.rules = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
      });
      default = { };
    };
    config.secretspec = {
      project = "h";
      scopes.github.secrets = [ "GITHUB_API_TOKEN" ];
    };
  };

  # The `wrap` a given extension set publishes into a target configuration. It is
  # published by wrappers' class module, so this goes through contributionsFor the
  # way a builder does; `hostcfg` is what the contribution context carries.
  argsWith = modules: hostcfg: usercfg: {
    wrap =
      spec:
      testLib.classWrap {
        eval = evalSubstrate modules;
        inherit spec;
        context = {
          pkgs = fakePkgs;
          inherit hostcfg usercfg;
        };
        configModules = lib.optional (builtins.elem ../../extensions/secrets/default.nix modules) secretsTarget;
      };
  };

  hostArgs = argsWith [
    ../../extensions/wrappers/default.nix
    ../../extensions/secrets/default.nix
  ] { name = "unsouled"; } null;

  # A contributor that does the smallest interesting thing: an option of its own,
  # and a chain fragment. `eggy` reads its spec back out, so a test can see what
  # a contributor was handed.
  eggyModule = {
    config.substrate.settings.wrappers.contributors.eggy = {
      priority = 5;
      options = {
        treat = lib.mkOption { type = lib.types.str; };
      };
      # The count, so a test can see what the contributor was told.
      prefix = ctx: spec: [ "eggy-${spec.eggy.treat}-${toString (lib.length ctx.forwarded)}" ];
      runtimeInputs = _ctx: spec: if spec.eggy.treat == "cup" then [ opFake ] else [ ];
      setup = _ctx: spec: if spec.eggy.treat == "tea" then "echo setup" else "";
    };
  };

  # A contributor that cannot honor env, to exercise the incompatible guard.
  pickyModule = {
    config.substrate.settings.wrappers.contributors.picky = {
      priority = 6;
      incompatible = [
        "env"
        "files"
      ];
      prefix = _ctx: _spec: [ "picky --" ];
    };
  };

  # A contributor that wraps the program in something of its own, and reports
  # what it was handed so a test can assert on it.
  swaddleModule = {
    config.substrate.settings.wrappers.contributors.swaddle = {
      priority = 7;
      options = {
        layer = lib.mkOption {
          type = lib.types.str;
          default = "one";
        };
      };
      # The layer it wrapped is in the store path, so a test can see which of two
      # program hooks ended up outside.
      program =
        _ctx: spec: inner:
        mkFakeDrv {
          type = "derivation";
          name = "swaddle-${spec.swaddle.layer}";
          outPath = "/nix/store/hash-swaddle-${spec.swaddle.layer}-${baseNameOf inner}";
          meta.mainProgram = spec.binName;
        };
    };
  };

  eggyArgs = argsWith [
    ../../extensions/wrappers/default.nix
    eggyModule
    pickyModule
    swaddleModule
  ] { name = "h"; } null;

in
runTests "Wrappers Extension Tests" {
  # --- pure text builders ---

  # An env name a shell cannot assign is rejected wherever it is written, not
  # where it would have failed at run time.
  rejectsInvalidEnvName = {
    check = throws (wrapPackage {
      package = fakePkg;
      env."bad-key" = "x";
    });
  };

  # A compiled stub carries the whole vocabulary as flags, so it is the same
  # escaping either way.
  binaryFlagsCarryTheWholeVocabulary = {
    check =
      binaryFlags (specOf {
        env.FOO = "bar baz";
        args = [ "--t" ];
        runtimeInputs = [ jqFake ];
        preHook = "echo hi";
      })
      == "--set FOO 'bar baz' --prefix PATH : /nix/store/hash-jq-1.7/bin --add-flags --t --run 'echo hi'";
  };

  # The chain ends at the core when there is one, and at the program when there is
  # nothing for a core to carry.
  toOuterSimple = {
    check =
      toOuter (specOf {
        chain = [ "uwsm app --" ];
        args = [ "--t" ];
      }) "" == "exec -a \"$0\" uwsm app -- @out@/bin/.foo-core \"$@\""
      &&
        toOuter (specOf { chain = [ "uwsm app --" ]; }) ""
        == "exec -a \"$0\" uwsm app -- /nix/store/hash-foo-1.0/bin/foo \"$@\"";
  };

  toOuterPostHookPropagatesExit = {
    check =
      let
        withCore = toOuter (specOf {
          args = [ "--t" ];
          postHook = "echo done";
        }) "";
        direct = toOuter (specOf { postHook = "echo done"; }) "";
      in
      # The program's status is captured and handed back, so the hook cannot
      # replace it -- and the same holds whether or not there is a core to exec.
      builtins.elem "( exec -a \"$0\" @out@/bin/.foo-core \"$@\" )" (lib.splitString "\n" withCore)
      && hasInfix "code=$?" withCore
      && hasInfix "exit $code" withCore
      && builtins.elem "( exec -a \"$0\" /nix/store/hash-foo-1.0/bin/foo \"$@\" )" (
        lib.splitString "\n" direct
      )
      && hasInfix "code=$?" direct
      && hasInfix "exit $code" direct;
  };

  # The environment is exported by the stub, above the chain, so a chain member can
  # read it -- that is what lets an arg name a variable secretspec has not injected
  # yet. Only what must happen innermost reaches the core.
  coreFlagsCarryOnlyArgsAndHooks = {
    check =
      coreFlags (specOf {
        env.FOO = "bar";
        args = [ "--t" ];
        runtimeInputs = [ jqFake ];
        preHook = "echo hi";
      }) == "--add-flags --t --run 'echo hi'";
  };

  # Nothing for the core to carry means no second file in the output at all.
  needsCoreOnlyForArgsAndPreHook = {
    check =
      !(needsCore (specOf {
        env.FOO = "bar";
        runtimeInputs = [ jqFake ];
      }))
      && needsCore (specOf {
        args = [ "--t" ];
      })
      && needsCore (specOf {
        preHook = "echo hi";
      });
  };

  # The stub exports the spec's environment and PATH, then runs the chain. The
  # spec's own runtimeInputs come before a contributor's, so PATH is what the
  # wrapped program needs rather than whatever a chain member added.

  # --- in-place stub pipeline ---

  # One shape: the stub is written beside the target and moved over it (writing
  # straight to $out/bin/foo would follow the tree's symlink into the store), and
  # the environment and PATH go in the stub where the chain can see them.
  stubInvocation = {
    check =
      let
        drv = wrapPackage {
          package = fakePkg;
          env.FOO = "bar baz";
          args = [ "--flag=a" ];
          runtimeInputs = [ jqFake ];
          preHook = "echo hi";
        };
      in
      hasInfix "substitute script:export FOO=" drv.postBuild
      && hasInfix ''PATH="/nix/store/hash-jq-1.7/bin:$PATH"'' drv.postBuild
      && hasInfix ''mv -f "$out/bin/.foo-outer" "$out/bin/foo"'' drv.postBuild
      # args and the pre-hook reach the core, which is what makes "$VAR" expand
      # after the chain has run
      && hasInfix ''makeWrapper /nix/store/hash-foo-1.0/bin/foo "$out/bin/.foo-core"'' drv.postBuild
      && hasInfix (
        "--add-flags " + lib.escapeShellArg (lib.concatStringsSep " " [ "--flag=a" ])
      ) drv.postBuild
      && hasInfix "--run 'echo hi'" drv.postBuild
      && drv.nativeBuildInputs == [ fakePkgs.makeWrapper ]
      && drv.paths == [ fakePkg ];
  };

  # Nothing for the core to carry: no second file in the output, and the stub execs
  # the program directly.
  bareWrapperHasNoSecondFile = {
    check =
      let
        drv = wrapPackage { package = fakePkg; };
      in
      !(hasInfix "makeWrapper" drv.postBuild)
      && hasInfix ''exec -a "$0" /nix/store/hash-foo-1.0/bin/foo "$@"'' drv.postBuild;
  };

  # `name` renames: the original executable is removed rather than left beside the
  # wrapper, so a wrapper is one command. `aliases` is the additive way to keep both.
  nameRenamesTheExecutable = {
    check =
      let
        drv = wrapPackage {
          package = fakePkg;
          name = "bar";
        };
      in
      hasInfix ''rm -f "$out/bin/foo"'' drv.postBuild
      && hasInfix ''mv -f "$out/bin/.bar-outer" "$out/bin/bar"'' drv.postBuild
      && drv.meta.mainProgram == "bar";
  };

  # Renaming to the name already there is not a rename, so nothing is removed.
  nameMatchingTheOriginalKeepsIt = {
    check =
      let
        drv = wrapPackage {
          package = fakePkg;
          name = "foo";
        };
      in
      !(hasInfix "rm -f" drv.postBuild)
      && hasInfix ''mv -f "$out/bin/.foo-outer" "$out/bin/foo"'' drv.postBuild
      && drv.meta.mainProgram == "foo";
  };

  # args are interpolated verbatim by makeWrapper's exec line, so "$VAR" stays
  # expandable at exec time. Callers pre-escape with lib.escapeShellArgs to opt
  # out and get a literal value.
  shellArgsExpandAtExecTime = {
    check =
      let
        drv = wrapPackage {
          package = fakePkg;
          args = [
            "--config"
            "\$EVERGREEN_CONFIG"
          ];
        };
        literal = wrapPackage {
          package = fakePkg;
          args = [
            (lib.escapeShellArgs [
              "--config"
              "\$EVERGREEN_CONFIG"
            ])
          ];
        };
        expandedFlags = coreFlags (specOf {
          args = [
            "--config"
            "\$EVERGREEN_CONFIG"
          ];
        });
        literalFlags = coreFlags (specOf {
          args = [
            (lib.escapeShellArgs [
              "--config"
              "\$EVERGREEN_CONFIG"
            ])
          ];
        });
      in
      # One escaping pass (the build shell's) leaves the value expandable;
      # a caller-escaped value is single-quoted in the exec line, opting out.
      expandedFlags == "--add-flags ${lib.escapeShellArg "--config \$EVERGREEN_CONFIG"}"
      && hasInfix literalFlags literal.postBuild
      && hasInfix expandedFlags drv.postBuild;
  };

  outputNameAndMeta = {
    check =
      let
        drv = wrapPackage { package = fakePkg; };
      in
      drv.name == "${lib.getName fakePkg}-wrapped" && drv.meta.mainProgram == "foo";
  };

  # A package with several outputs says so in meta.outputsToInstall. The wrapper
  # is one output, so it must not inherit that list: buildenv would then ask for
  # a `man` output the wrapper does not build and fail with "attribute 'man'
  # missing" where the package is installed.
  outputIsAlwaysExactlyOut = {
    check =
      let
        multiOut = mkFakeDrv {
          type = "derivation";
          pname = "multi";
          version = "1.0";
          outPath = "/nix/store/hash-multi-1.0";
          meta.mainProgram = "multi";
          meta.outputsToInstall = [
            "out"
            "man"
          ];
        };
        drv = wrapPackage { package = multiOut; };
      in
      drv.meta.outputsToInstall == [ "out" ] && drv.meta.mainProgram == "multi";
  };

  # symlinkJoin links the stringified path, which for a package is its default
  # output alone. So a package that keeps its man pages in its own output (as
  # rclone and fzf do) needs that output named as a path too, or wrapping drops
  # the manual from a tree meant to stand in for the package.
  treeCarriesDeclaredOutputs = {
    check =
      let
        multiOut = mkFakeDrv {
          type = "derivation";
          pname = "multi";
          version = "1.0";
          outPath = "/nix/store/hash-multi-1.0";
          man = "/nix/store/hash-multi-man";
          meta.mainProgram = "multi";
          meta.outputsToInstall = [
            "out"
            "man"
          ];
        };
        drv = wrapPackage { package = multiOut; };
      in
      drv.paths == [
        multiOut
        multiOut.man
      ];
  };

  # The declaration is what is followed, not the full output list: ghostty holds
  # man, terminfo and vim outputs and installs none of them, so its wrapper links
  # its default output and stops there.
  treeSkipsUndeclaredOutputs = {
    check =
      let
        held = mkFakeDrv {
          type = "derivation";
          pname = "held";
          version = "1.0";
          outPath = "/nix/store/hash-held-1.0";
          man = "/nix/store/hash-held-man";
          meta.mainProgram = "held";
          meta.outputsToInstall = [ "out" ];
        };
        drv = wrapPackage { package = held; };
      in
      drv.paths == [ held ];
  };

  # Desktop patching happens for every wrapper, chained or not: adding a prefix or
  # a contributor no longer changes what the output contains.
  patchesDesktopEntries = {
    check =
      let
        drv = wrapPackage { package = fakePkg; };
      in
      hasInfix ''rm -rf "$out/share/applications"'' drv.postBuild
      && hasInfix ''sed "s|/nix/store/hash-foo-1.0|$out|g"'' drv.postBuild;
  };

  exeSelectsBinary = {
    check =
      hasInfix ''makeWrapper /nix/store/hash-foo-1.0/bin/helper "$out/bin/.helper-core"''
        (wrapPackage {
          package = fakePkg;
          exe = "helper";
          args = [ "--x" ];
        }).postBuild;
  };

  filesAndAliases = {
    check =
      let
        drv = wrapPackage {
          package = fakePkg;
          files."mpv.conf".text = "vo=gpu";
          aliases = [ "foo2" ];
        };
      in
      hasInfix ''ln -s text:mpv.conf "$out/mpv.conf"'' drv.postBuild
      && hasInfix ''ln -s foo "$out/bin/foo2"'' drv.postBuild
      && drv.passthru.files."mpv.conf" == "text:mpv.conf";
  };

  shellRejectsUnknownKeys = {
    check = throws (wrapPackage {
      package = fakePkg;
      pkg = fakePkg;
    });
  };

  shellRequiresPackage = {
    check = throws (wrapPackage {
      env.FOO = "bar";
    });
  };

  # --- contributors ---

  # A chain fragment is what a contributor contributes: it becomes the stub's exec
  # line, ahead of the program. Nothing here needs a second file -- only args and a
  # pre-hook do -- so the wrapper is still one executable.
  contributorPrefixBecomesTheChain = {
    check =
      let
        drv = eggyArgs.wrap {
          package = fakePkg;
          eggy.treat = "cup";
        };
      in
      hasInfix ''exec -a "$0" eggy-cup-0 ${exe} "$@"'' drv.body
      && hasInfix "substitute script:" drv.body
      # nothing for the core to carry, so the placeholder is not substituted
      && !(hasInfix "@out@" drv.body)
      # and the wrapper is the package tree with one executable replaced
      && drv.paths == [ fakePkg ];
  };

  contributorSetupRunsBeforeTheChain = {
    check =
      let
        drv = eggyArgs.wrap {
          package = fakePkg;
          eggy.treat = "tea";
        };
        stub = stubText drv;
      in
      # the setup snippet is in the stub, and it precedes the chain
      hasInfix "echo setup" (lib.head (lib.splitString "exec -a" stub));
  };

  contributorRuntimeInputsJoinPath = {
    check =
      hasInfix ''PATH="/nix/store/hash-op-2.32.0/bin:$PATH"''
        (eggyArgs.wrap {
          package = fakePkg;
          eggy.treat = "cup";
        }).body;
  };

  # Two contributors, ordered by priority: the lower one leads the chain. A
  # tie is an error rather than an arbitrary order.
  contributorsAreOrderedByPriority = {
    check =
      let
        drv = eggyArgs.wrap {
          package = fakePkg;
          eggy.treat = "cup";
          picky = { };
        };
      in
      hasInfix "eggy-cup-0 picky --" drv.body;
  };

  contributorPriorityTieIsAnError = {
    check = throws (
      (argsWith [
        ../../extensions/wrappers/default.nix
        eggyModule
        {
          config.substrate.settings.wrappers.contributors.twin = {
            priority = 5;
            prefix = _ctx: _spec: [ "twin --" ];
          };
        }
      ] { name = "h"; } null).wrap
        {
          package = fakePkg;
          eggy.treat = "cup";
          twin = { };
        }
    );
  };

  # A contributor that is not registered is an eval error, never a silently
  # ignored key.
  unknownContributorKeyIsAnError = {
    check = throws (wrapPackage {
      package = fakePkg;
      nosuchthing.treat = "cup";
    });
  };

  contributorOptionsAreValidated = {
    check = throws (
      eggyArgs.wrap {
        package = fakePkg;
        eggy.bogus = "x";
      }
    );
  };

  # The registry is forced as the class module closes over it, so a broken entry
  # says so before anyone names it.
  contributorMustDeclarePriority = {
    check = throws (
      (argsWith [
        ../../extensions/wrappers/default.nix
        {
          config.substrate.settings.wrappers.contributors.priorityless = {
            prefix = _ctx: _spec: [ ];
          };
        }
      ] { name = "h"; } null).wrap
        { package = fakePkg; }
    );
  };

  # "May not ignore anything, need not accept everything": a field a
  # contributor declares it cannot honor is an error naming the contributor.
  incompatibleFieldIsAnError = {
    check = throws (
      eggyArgs.wrap {
        package = fakePkg;
        picky = { };
        env.A = "1";
      }
    );
  };

  incompatibleFieldUnsetIsFine = {
    check =
      (eggyArgs.wrap {
        package = fakePkg;
        picky = { };
      }).meta.mainProgram == "foo";
  };

  # A contributor may wrap the program in something of its own; the core renders
  # everything else around whatever it produced.
  contributorProgramReplacesTheWrappedPackage = {
    check =
      let
        drv = eggyArgs.wrap {
          package = fakePkg;
          eggy.treat = "cup";
          swaddle = { };
        };
      in
      # What the wrapper runs is the swaddle, not the package; the stub's exec line
      # names it, ahead of the caller's own arguments.
      hasInfix ''exec -a "$0" eggy-cup-0 /nix/store/hash-swaddle-one-hash-foo-1.0/bin/foo "$@"'' drv.body
      # the wrapper still names and reports the package the caller asked for
      && drv.passthru.wrapped.outPath == fakePkg.outPath;
  };

  # Two contributors that both supply a program: the inner one (higher priority
  # number) is applied first, so priority order also wraps outward.
  contributorProgramsComposeInnermostFirst = {
    check =
      let
        drv = argsWith [
          ../../extensions/wrappers/default.nix
          swaddleModule
          {
            config.substrate.settings.wrappers.contributors.swaddle2 = {
              priority = 8;
              program =
                _ctx: spec: inner:
                mkFakeDrv {
                  type = "derivation";
                  outPath = "/nix/store/hash-swaddle2";
                  meta.mainProgram = spec.binName;
                  wrapped = inner;
                };
            };
          }
        ] { name = "h"; } null;
        wrapper = drv.wrap {
          package = fakePkg;
          swaddle = { };
          swaddle2 = { };
        };
      in
      # swaddle2 (priority 8) wrapped the package first; swaddle (7) wrapped
      # that, so swaddle is what runs and swaddle2 is inside it
      hasInfix "/nix/store/hash-swaddle-one-hash-swaddle2/bin/foo" wrapper.body;
  };

  # Every contributor is handed the names the others advertise, which is how one
  # that scrubs the environment can pass them on. eggy counts what it was told.
  # A contributor sees the names the core advertises, so one that scrubs the
  # environment can pass them on.
  contributorSeesForwardedEnvNames = {
    check =
      let
        secretArgs = argsWith [
          ../../extensions/wrappers/default.nix
          ../../extensions/secrets/default.nix
          eggyModule
        ] { name = "h"; } null;
        withoutSecrets = eggyArgs.wrap {
          package = fakePkg;
          eggy.treat = "cup";
        };
        withSecret = secretArgs.wrap {
          package = fakePkg;
          eggy.treat = "cup";
          secrets.scope = "github";
        };
        withSecretAndEnv = secretArgs.wrap {
          package = fakePkg;
          env.A = "1";
          eggy.treat = "cup";
          secrets.scope = "github";
        };
      in
      # Only the core advertises names, and only the spec sets them: secrets names
      # no variables, because a scope's are declared where they are forwarded.
      hasInfix "eggy-cup-0" withoutSecrets.body
      && hasInfix "eggy-cup-0" withSecret.body
      && hasInfix "eggy-cup-1" withSecretAndEnv.body;
  };

  # --- shapes ---

  # A prefix is a chain fragment like any other, and lands in the stub's exec line.
  # It changes what the wrapper runs, not what the output is: still the package
  # tree, still one executable, still the same name.
  prefixBecomesTheChain = {
    check =
      let
        drv = wrapPackage {
          package = fakePkg;
          prefix = [ "uwsm app --" ];
        };
      in
      drv.meta.mainProgram == "foo"
      && drv.name == "${lib.getName fakePkg}-wrapped"
      && hasInfix ''substitute script:exec -a "$0" uwsm app -- ${exe} "$@"'' drv.body
      && drv.paths == [ fakePkg ];
  };

  # With a prefix AND something for the core to carry, the chain ends at the core
  # and the args land on the program itself.
  prefixWithArgsEndsAtTheCore = {
    check =
      let
        drv = wrapPackage {
          package = fakePkg;
          prefix = [ "x --" ];
          args = [ "--t" ];
          postHook = "echo done";
        };
      in
      hasInfix ''substitute script:( exec -a "$0" x -- @out@/bin/.foo-core "$@" )'' drv.body
      && hasInfix ''makeWrapper ${exe} "$out/bin/.foo-core" --add-flags ${lib.escapeShellArg "--t"} --inherit-argv0'' drv.body
      && hasInfix "exit $code" drv.body;
  };

  # A wrapper carries the whole vocabulary over whatever it wraps: the same
  # fields, the same escaping, whether the package is a program or a script.
  carriesTheVocabularyOverAnything = {
    check =
      let
        drv = wrapPackage {
          package = fakePkg;
          name = "ff";
          env.GREET = "hi";
          args = [ "--fast" ];
          files."ff.conf".text = "x=1";
        };
      in
      drv.meta.mainProgram == "ff"
      && hasInfix "export GREET=hi" drv.body
      && hasInfix ''ln -s text:ff.conf "$out/ff.conf"'' drv.body
      && hasInfix "--add-flags" drv.body
      && drv.passthru.wrapped.outPath == fakePkg.outPath;
  };

  # A file's resolved path is what an env function receives, and it is linked
  # into the wrapper under the name it was declared with.
  filesEnvFunctionSelfRef = {
    check =
      let
        drv = wrapPackage {
          package = fakePkg;
          files."mpv.conf".text = "vo=gpu";
          env.MPV_CONFIG = f: f."mpv.conf";
        };
      in
      hasInfix "export MPV_CONFIG=text:mpv.conf" drv.postBuild
      && hasInfix ''ln -s text:mpv.conf "$out/mpv.conf"'' drv.postBuild;
  };

  # --- passthru contract ---

  passthruMerged = {
    check =
      let
        drv = wrapPackage {
          package = fakePkg;
          passthru.custom = "yes";
        };
      in
      drv.passthru.custom == "yes" && drv.passthru.wrapped.outPath == fakePkg.outPath;
  };

  passthruOverrideRebuilds = {
    check =
      let
        drv = wrapPackage { package = fakePkg; };
        rebuilt = drv.passthru.override { version = "9.9"; };
      in
      # rerun rebuilds the whole pipeline around the overridden package
      rebuilt ? postBuild && rebuilt.passthru.wrapped.version == "9.9" && rebuilt.name == drv.name;
  };

  # --- binary stub pipeline ---

  # --- wiring ---

  wrapArrivesAsModuleArg = {
    check = hostArgs ? wrap && (hostArgs.wrap { package = fakePkg; }) ? postBuild;
  };

  # Nesting is just nesting: two wrappers, each rendering itself.
  nestingIsExplicit = {
    check =
      let
        inner = wrapPackage { package = fakePkg; };
        outer = wrapPackage {
          package = inner;
          env.GREET = "hi";
        };
      in
      outer.passthru.wrapped.outPath == inner.outPath
      && inner.outPath != fakePkg.outPath
      && hasInfix "export GREET=hi" outer.postBuild;
  };

  # --- secrets, as a contributor ---

  secretsContributesTheInvocation = {
    check =
      let
        drv = hostArgs.wrap {
          package = fakePkg;
          env.GREET = "hi";
          args = [ "--fast" ];
          secrets.scope = "github";
        };
      in
      # one derivation, one chain: the invocation, then the core carrying env
      # and args so "$VAR" expands after secretspec resolved it
      hasInfix
        ''makeWrapper ${exe} "$out/bin/.foo-core" --add-flags ${lib.escapeShellArg "--fast"} --inherit-argv0''
        drv.body
      && hasInfix "export GREET=hi" drv.body
      && hasInfix "exec -a \"\$0\" /fake/secretspec/bin/secretspec run --file ${fakeStoreManifest} --scope github" drv.body
      && hasInfix ''-- @out@/bin/.foo-core "$@"'' drv.body
      && drv.passthru.wrapped.outPath == fakePkg.outPath;
  };

  # The spec's own prefix is innermost, so a contributor wraps the whole invocation:
  # secretspec resolves the scope, and the launcher runs inside it.
  secretsLeadsTheSpecsOwnPrefix = {
    check =
      hasInfix
        "secretspec run --file ${fakeStoreManifest} --scope github --caller substrate --caller-operation run --reason 'runtime resolution for scope github' -- uwsm app -- ${exe} \"$@\""
        (hostArgs.wrap {
          package = fakePkg;
          prefix = [ "uwsm app --" ];
          secrets.scope = "github";
        }).body;
  };

  secretsReasonIsConfigurable = {
    check =
      hasInfix "--reason ${lib.escapeShellArg "because"}"
        (hostArgs.wrap {
          package = fakePkg;
          secrets = {
            scope = "github";
            reason = "because";
          };
        }).body;
  };

  secretsManifestFromSpecWins = {
    check =
      hasInfix "--file /somewhere/else.toml"
        (hostArgs.wrap {
          package = fakePkg;
          secrets = {
            scope = "github";
            manifest = "/somewhere/else.toml";
          };
        }).body;
  };

  # The wrapper language is not the contributor's: those fields belong to the
  # spec, and a scope is not one of them.
  secretsRejectsTheWrapperLanguage = {
    check = throws (
      hostArgs.wrap {
        package = fakePkg;
        secrets = {
          scope = "github";
          env.A = "1";
        };
      }
    );
  };

  secretsScopeMustBeDeclared = {
    check = throws (
      hostArgs.wrap {
        package = fakePkg;
        secrets.scope = "nosuchscope";
      }
    );
  };

  secretsResolvesEnvFunctionsOverFiles = {
    check =
      hasInfix "export CONFIG=text:app.conf"
        (hostArgs.wrap {
          package = fakePkg;
          files."app.conf".text = "k=v\n";
          env.CONFIG = f: f."app.conf";
          secrets.scope = "github";
        }).body;
  };

  secretsUserBuildNeedsNoXdgFallback = {
    check =
      let
        userArgs =
          (argsWith [
            ../../extensions/wrappers/default.nix
            ../../extensions/secrets/default.nix
          ] { name = "u"; } { name = "u"; }).wrap;
      in
      !(hasInfix "XDG_CONFIG_HOME"
        (userArgs {
          package = fakePkg;
          secrets.scope = "github";
        }).body
      );
  };

  # --- real-nixpkgs integration (pure eval, nothing built) ---

  realDerivationsProducePaths = {
    check =
      let
        bare = realWrap { package = pkgs.hello; };
        chained = realWrap {
          package = pkgs.hello;
          prefix = [ "launcher --" ];
        };
        binary = realWrap {
          package = pkgs.hello;
          stub = "makeBinaryWrapper";
        };
      in
      lib.isString bare.outPath
      && lib.isString chained.outPath
      && lib.isString binary.outPath
      && bare.meta.mainProgram == "hello"
      && chained.passthru.wrapped.outPath == pkgs.hello.outPath
      # package is required: a wrapper wraps a package.
      && !(builtins.tryEval (realWrap { })).success;
  };
}
