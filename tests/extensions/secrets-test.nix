# Tests for substrate secrets extension
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

  manifest = import ../../extensions/secrets/manifest.nix { inherit lib; };
  inherit (manifest)
    render
    ;
  inherit (lib.strings) hasInfix;

  sampleRender = render {
    project = "unsouled";
    defaultProviders = [ "team" ];
    entries = {
      GITHUB_TOKEN = {
        description = "GitHub API token";
        providers = [ "team" ];
        ref = {
          item = "GitHub";
          field = "token";
          vault = null;
          section = null;
        };
        required = true;
        default = null;
        prompt = false;
        asPath = false;
      };
      CA_BUNDLE = {
        description = "TLS CA bundle";
        asPath = true;
        required = true;
        default = null;
        prompt = false;
        providers = [ ];
        ref = null;
      };
      SESSION_PASSWORD = {
        prompt = true;
        required = false;
        description = "Password typed in when missing";
        default = null;
        asPath = false;
        providers = [ ];
        ref = null;
      };
    };
    providers = {
      team = {
        uri = "onepassword://Prod";
        credentials = {
          service_account_token = "keyring";
        };
      };
      local = {
        uri = "keyring://";
        credentials = { };
      };
    };
    scopes = {
      github = {
        secrets = [ "GITHUB_TOKEN" ];
      };
    };
  };

  minimalRender = render {
    project = "blackflame";
    entries.FOO = {
      description = "just foo";
      required = true;
      default = null;
      prompt = false;
      asPath = false;
      providers = [ ];
      ref = null;
    };
  };

  throws = expr: !(builtins.tryEval (builtins.deepSeq expr expr)).success;
  # raw option values keep any mkIf wrapper; tests read the content of
  # true conditions
  unwrap = v: if v ? _type && v._type == "if" && v.condition then unwrap v.content else v;

  optionsEval = lib.evalModules {
    modules = [
      ../../extensions/secrets/options.nix
      {
        config.secretspec = {
          entries.GITHUB_TOKEN.description = "from module one";
          entries.API_KEY = {
            description = "API key";
            required = false;
          };
          providers.team.uri = "onepassword://Prod";
        };
      }
      {
        config.secretspec = {
          entries.CA_BUNDLE = {
            description = "TLS CA bundle";
            asPath = true;
          };
          providers.team.credentials.service_account_token = "keyring";
          providers.local.uri = "keyring://";
          scopes.api.secrets = [ "GITHUB_TOKEN" ];
          defaultProviders = [ "team" ];
        };
      }
    ];
  };

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

  # Reachable only through the target pkgs, so a test can prove the provider
  # packages are taken from the configuration's own package set.
  fakeOpPkg = mkFakeDrv {
    pname = "1password-cli";
    version = "2.32.0";
    outPath = "/nix/store/hash-op-2.32.0";
    meta.mainProgram = "op";
  };

  fakePkgs = {
    _1password-cli = fakeOpPkg;
    secretspec = "/fake/secretspec";
    makeWrapper = "/fake/makeWrapper";
    coreutils = "/fake/coreutils";
    writeShellScript = _name: text: "script:${text}";
    # the in-place backends copy the package tree; the fake stands in for lndir
    # symlinkJoin is how every wrapper is built now, so `body` is the postBuild
    # script: the tests read the build script, not which builder took it.
    symlinkJoin = args: mkFakeDrv (args // { body = args.postBuild or ""; });
    # Real writeText returns a store path, so the fake does too: that path is what
    # ends up in unit ExecStart, tmpfiles targets, and $SECRETSPEC_FILE.
    writeText = name: _: "/nix/store/hash-${name}";
    writeShellApplication =
      {
        name,
        text,
        runtimeInputs ? [ ],
        ...
      }:
      # outPath embeds the script text so ExecStart interpolations are
      # inspectable, and each runtimeInputs path so a test can see what the
      # script puts on its PATH.
      mkFakeDrv {
        inherit name text runtimeInputs;
        outPath = "drv:" + text + lib.concatMapStringsSep "" (p: ":${toString p}/bin") runtimeInputs;
      };
    runCommand =
      name: args: body:
      mkFakeDrv (
        args
        // {
          inherit name body;
        }
      );
  };

  fakePkg = mkFakeDrv {
    type = "derivation";
    pname = "foo";
    version = "1.0";
    outPath = "/nix/store/hash-foo-1.0";
    meta.mainProgram = "foo";
  };

  # --- direct class-module evals (NixOS + fake HM context) ---

  # Where the manifest lives when secretspec.manifestPath is null: its store path.
  fakeStoreManifest = "/nix/store/hash-secretspec.toml";

  # Option stubs and declarations for a NixOS-class eval, shared by the direct
  # class-module tests and the contributed-module tests so both drive the same
  # configuration.
  nixosStubs = {
    options.networking.hostName = lib.mkOption {
      type = lib.types.str;
      default = "hosts";
    };
    # attrsOf with an empty default, like the real option: an unset placement
    # then reads as {} rather than an option with no value.
    options.environment.etc = lib.mkOption {
      type = lib.types.attrsOf lib.types.raw;
      default = { };
    };
    options.environment.systemPackages = lib.mkOption { type = lib.types.raw; };
    options.systemd.services = lib.mkOption { type = lib.types.raw; };
    options.systemd.tmpfiles = lib.mkOption {
      type = lib.types.submodule (_: {
        options.rules = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
      });
      default = { };
    };
    # project is left to the class module's default, so a test can see that it
    # reads the class's own identity.
    config.secretspec = {
      entries.FOO = {
        description = "foo";
        ref.item = "x";
        file = { };
      };
      entries.BAR = {
        description = "bar";
        ref.item = "y";
      };
    };
  };

  hmStubs = {
    options.home.username = lib.mkOption {
      type = lib.types.str;
      default = "craig";
    };
    options.home.homeDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/home/craig";
    };
    options.home.packages = lib.mkOption { type = lib.types.raw; };
    options.home.sessionVariables = lib.mkOption { type = lib.types.raw; };
    options.systemd.user.services = lib.mkOption { type = lib.types.raw; };
    options.systemd.user.tmpfiles = lib.mkOption {
      type = lib.types.submodule (_: {
        options.rules = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
      });
      default = { };
    };
    options.systemd.user.startServices = lib.mkOption {
      type = lib.types.raw;
      default = "no";
    };
    options.xdg.configHome = lib.mkOption {
      type = lib.types.str;
      default = "/home/craig/.config";
    };
    options.xdg.configFile = lib.mkOption {
      type = lib.types.attrsOf lib.types.raw;
      default = { };
    };
    config.secretspec.entries.GITHUB_TOKEN = {
      description = "GitHub token";
      ref.item = "x";
      file = { };
    };
  };

  nixEval = lib.evalModules {
    modules = [
      (import ../../extensions/secrets/nixos-module.nix { inherit lib; })
      nixosStubs
    ];
    specialArgs = {
      pkgs = fakePkgs;
    };
  };

  hmEval = lib.evalModules {
    modules = [
      (import ../../extensions/secrets/home-manager-module.nix { inherit lib; })
      hmStubs
    ];
    specialArgs = {
      pkgs = fakePkgs;
    };
  };

  # The same two configurations with the manifest moved: a name under /etc, a
  # path outside /etc, a path outside the config home, and a path inside it.
  mkPathEval =
    module: stubs: manifestPath:
    lib.evalModules {
      modules = [
        (import ../../extensions/secrets/${module} { inherit lib; })
        stubs
        {
          config.secretspec.manifestPath = manifestPath;
        }
      ];
      specialArgs = {
        pkgs = fakePkgs;
      };
    };

  nixEtcNameEval = mkPathEval "nixos-module.nix" nixosStubs "/etc/secrets.toml";
  nixOutsideEtcEval = mkPathEval "nixos-module.nix" nixosStubs "/var/lib/secrets/secretspec.toml";
  hmInHomeEval =
    mkPathEval "home-manager-module.nix" hmStubs
      "/home/craig/.config/secrets/secretspec.toml";
  hmOutsideHomeEval =
    mkPathEval "home-manager-module.nix" hmStubs
      "/home/craig/.local/state/secrets/secretspec.toml";

  eval = evalSubstrate [ ../../extensions/secrets/default.nix ];

  # `wrap` reaches a target configuration through wrappers' class module, and a
  # secrets hook reads the secretspec options declared beside it. Those options
  # come from the secrets extension's own class module (the same one that declares
  # them in a real NixOS configuration); this only adds the declarations a bare
  # eval needs and a declared scope to read. No manifest path in the spec, and no
  # settings published back into substrate.
  secretsTarget = lib.recursiveUpdate nixosStubs {
    config.secretspec = {
      scopes.github.secrets = [ "GITHUB_API_TOKEN" ];
      # A provider, and the CLI it shells out to, declared together. The entry
      # reaches it through defaultProviders.
      providers.op = {
        uri = "onepassword://Infra";
        package = fakeOpPkg;
      };
      defaultProviders = [ "op" ];
    };
  };

  # The same configuration with no provider declaring a CLI, so the derived PATH
  # is empty even though a provider exists.
  noProviderPackageTarget = nixosStubs // {
    config.secretspec = {
      scopes.github.secrets = [ "GITHUB_API_TOKEN" ];
      providers.op.uri = "onepassword://Infra";
    };
  };

  wrapsEval = evalSubstrate [
    ../../extensions/wrappers/default.nix
    ../../extensions/secrets/default.nix
  ];

  packagesWrapsEval = wrapsEval;

  wrapsArgsFor =
    {
      substrateEval,
      usercfg ? null,
      target ? secretsTarget,
      class ? "nixos",
    }:
    {
      wrap =
        spec:
        testLib.classWrap {
          eval = substrateEval;
          inherit spec class;
          context = {
            pkgs = fakePkgs;
            inherit usercfg;
          };
          configModules = [ target ];
        };
    };

  wrapsArgs = wrapsArgsFor { substrateEval = wrapsEval; };

  # No scope declared: the wrapper must say so at eval time rather than leaving
  # it to secretspec at exec time.
  noScopesArgs = wrapsArgsFor {
    substrateEval = wrapsEval;
    target = nixosStubs;
  };

  # A target configuration with no secretspec at all: the extension's class module
  # is not loaded, so there is nothing to read a manifest from.
  noSecretsArgs = wrapsArgsFor {
    substrateEval = wrapsEval;
    target = { };
  };

  packagesWrapsArgs = wrapsArgsFor { substrateEval = packagesWrapsEval; };

  contributed = eval.config.substrate.lib.contributionsFor "nixos" { };
  contributedUsers = eval.config.substrate.lib.contributionsFor "homeManager" { };

  # The contributed modules as the builder loads them, so the injection of
  # Provider CLIs are exercised through the real contribution path.
  contributedNixosEval = lib.evalModules {
    modules = contributed ++ [ nixosStubs ];
    specialArgs = {
      pkgs = fakePkgs;
    };
  };

  contributedHmEval = lib.evalModules {
    modules = contributedUsers ++ [ hmStubs ];
    specialArgs = {
      pkgs = fakePkgs;
    };
  };

  # The class modules as the builder loads them, with a provider declaring a CLI.
  packagesEval = evalSubstrate [ ../../extensions/secrets/default.nix ];

  # A configuration whose declared entries reach a provider that declares its CLI.
  # recursiveUpdate, not //: these are modules, and `//` would replace the whole
  # config subtree, taking the entries the stubs declare with it.
  withProvider =
    stubs:
    lib.recursiveUpdate stubs {
      config.secretspec = {
        providers.op = {
          uri = "onepassword://Infra";
          package = fakeOpPkg;
        };
        defaultProviders = [ "op" ];
      };
    };

  packagesNixosStubs = withProvider nixosStubs;
  packagesHmStubs = withProvider hmStubs;

  packagesNixosEval = lib.evalModules {
    modules = packagesEval.config.substrate.lib.contributionsFor "nixos" { } ++ [ packagesNixosStubs ];
    specialArgs = {
      pkgs = fakePkgs;
    };
  };

  packagesHmEval = lib.evalModules {
    modules = packagesEval.config.substrate.lib.contributionsFor "homeManager" { } ++ [
      packagesHmStubs
    ];
    specialArgs = {
      pkgs = fakePkgs;
    };
  };
in
runTests "Secrets Extension Tests" {
  # --- manifest rendering (pure) ---

  # [project] needs a revision for secretspec to load the manifest at all; the
  # order of the two keys is not significant.
  renderProjectHeader = {
    check =
      lib.strings.hasPrefix "[project]\n" sampleRender
      && hasInfix ''name = "unsouled"'' sampleRender
      && hasInfix ''revision = "1.0"'' sampleRender;
  };

  renderInlineSecretTable = {
    check = hasInfix ''GITHUB_TOKEN = { description = "GitHub API token", providers = [ "team" ], ref = { field = "token", item = "GitHub" } }'' sampleRender;
  };

  renderDefaultsProviders = {
    check = hasInfix ''defaults = { providers = [ "team" ] }'' sampleRender;
  };

  renderAsPathSnakeCase = {
    check = hasInfix ''CA_BUNDLE = { as_path = true, description = "TLS CA bundle" }'' sampleRender;
  };

  renderRequiredFalsePreserved = {
    check = hasInfix ''SESSION_PASSWORD = { description = "Password typed in when missing", prompt = true, required = false }'' sampleRender;
  };

  renderProviderStringVsTable = {
    check =
      hasInfix ''local = "keyring://"'' sampleRender
      && hasInfix ''team = { credentials = { service_account_token = "keyring" }, uri = "onepassword://Prod" }'' sampleRender;
  };

  # A credential may also pin an explicit address in the source provider, so
  # the value can live at a path of its own instead of the convention address.
  renderCredentialAddress = {
    check =
      let
        out = render {
          project = "unsouled";
          providers.team = {
            uri = "onepassword://Prod";
            credentials.service_account_token = {
              provider = "file:/etc/secrets";
              ref.item = "service_account_token";
            };
          };
          entries.FOO.description = "foo";
        };
      in
      hasInfix ''team = { credentials = { service_account_token = { provider = "file:/etc/secrets", ref = { item = "service_account_token" } } }, uri = "onepassword://Prod" }'' out;
  };

  # Unset coordinates are dropped, never rendered as empty strings.
  renderCredentialDropsUnsetCoords = {
    check =
      let
        out = render {
          project = "unsouled";
          providers.team = {
            uri = "onepassword://Prod";
            credentials.service_account_token = {
              provider = "keyring://";
              ref = {
                item = "op";
                field = "token";
              };
            };
          };
          entries.FOO.description = "foo";
        };
      in
      hasInfix ''credentials = { service_account_token = { provider = "keyring://", ref = { field = "token", item = "op" } } }'' out
      && !(hasInfix ''vault = ""'' out)
      && !(hasInfix ''section = ""'' out);
  };

  renderEntryRefWithVersion = {
    check =
      let
        out = render {
          project = "p";
          entries.FOO = {
            description = "foo";
            ref = {
              item = "Postgres";
              version = "3";
            };
          };
        };
      in
      hasInfix ''FOO = { description = "foo", ref = { item = "Postgres", version = "3" } }'' out;
  };

  renderScopes = {
    check = hasInfix "[scopes.github]\nsecrets = [ \"GITHUB_TOKEN\" ]" sampleRender;
  };

  renderComposedEntry = {
    check =
      let
        out = render {
          project = "p";
          entries = {
            GITHUB_API_TOKEN = {
              description = "GitHub API token";
              ref = {
                vault = "Craig";
                item = "Github";
                field = "api_token";
              };
            };
            TOKENS = {
              description = "Git credentials";
              composed = "access-tokens = github.com=\${GITHUB_API_TOKEN}";
              file = { };
            };
          };
        };
      in
      hasInfix ''GITHUB_API_TOKEN = { description = "GitHub API token", ref = { field = "api_token", item = "Github", vault = "Craig" } }'' out
      && hasInfix ''TOKENS = { composed = "access-tokens = github.com=''${GITHUB_API_TOKEN}", description = "Git credentials" }'' out;
  };

  renderRejectsComposedWithRef = {
    check = throws (render {
      project = "p";
      entries.BAD = {
        description = "bad";
        composed = "x";
        ref = {
          item = "y";
        };
      };
    });
  };

  renderRejectsComposedWithProviders = {
    check = throws (render {
      project = "p";
      entries.BAD = {
        description = "bad";
        composed = "x";
        providers = [ "p" ];
      };
    });
  };

  renderRejectsComposedWithDefault = {
    check = throws (render {
      project = "p";
      entries.BAD = {
        description = "bad";
        composed = "x";
        default = "y";
      };
    });
  };

  renderComposedWithAsPath = {
    check =
      let
        out = render {
          project = "p";
          entries.TPL = {
            description = "template";
            composed = "\${X}";
            asPath = true;
          };
        };
      in
      hasInfix ''TPL = { as_path = true, composed = "''${X}", description = "template" }'' out;
  };

  renderOmitsEmptySections = {
    check =
      !(hasInfix "[providers]" minimalRender)
      && !(hasInfix "[scopes" minimalRender)
      && hasInfix "[profiles.default]" minimalRender;
  };

  renderEscapesQuotesAndBackslashes = {
    check =
      let
        out = render {
          project = "a\\b";
          entries.FOO.description = ''say "hi" \ then'';
        };
      in
      hasInfix ''name = "a\\b"'' out && hasInfix ''FOO = { description = "say \"hi\" \\ then" }'' out;
  };

  # --- validation failures ---

  rejectScopeReferencingUnknownSecret = {
    check = throws (render {
      project = "x";
      entries.FOO.description = "foo";
      scopes.bad.secrets = [ "MISSING" ];
    });
  };

  rejectRefWithoutItem = {
    check = throws (render {
      project = "x";
      entries.FOO = {
        description = "foo";
        ref = {
          item = "";
          field = "token";
        };
      };
    });
  };

  rejectInvalidEntryName = {
    check = throws (render {
      project = "x";
      entries."bad-name" = { };
    });
  };

  rejectInvalidProviderName = {
    check = throws (render {
      project = "x";
      providers."9lives" = {
        uri = "keyring://";
      };
    });
  };

  rejectProviderWithoutUri = {
    check = throws (render {
      project = "x";
      providers.empty = { };
    });
  };

  # secretspec rejects the whole manifest when a secret has no description.
  rejectEntryWithoutDescription = {
    check = throws (render {
      project = "x";
      entries.FOO = { };
    });
  };

  rejectCredentialAddressWithoutItem = {
    check = throws (render {
      project = "x";
      providers.team = {
        uri = "onepassword://Prod";
        credentials.service_account_token = {
          provider = "file:/etc/secrets";
          ref.field = "token";
        };
      };
      entries.FOO.description = "foo";
    });
  };

  # --- option module (target-side, merged across class modules) ---

  optionsMergeAcrossModules = {
    check =
      let
        cfg = optionsEval.config.secretspec;
      in
      builtins.length (builtins.attrNames cfg.entries) == 3
      && cfg.entries.GITHUB_TOKEN.description == "from module one"
      && cfg.entries.API_KEY.required == false
      && cfg.entries.CA_BUNDLE.asPath == true
      && cfg.providers.team.credentials.service_account_token == "keyring";
  };

  optionsRenderMerged = {
    check =
      let
        cfg = optionsEval.config.secretspec;
        out = render {
          project = "unsouled";
          inherit (cfg)
            entries
            providers
            scopes
            defaultProviders
            ;
        };
      in
      hasInfix "[scopes.api]\nsecrets = [ \"GITHUB_TOKEN\" ]" out
      && hasInfix ''API_KEY = { description = "API key", required = false }'' out;
  };

  optionsAcceptCredentialAddress = {
    check =
      let
        evaluated = lib.evalModules {
          modules = [
            ../../extensions/secrets/options.nix
            {
              config.secretspec = {
                entries.FOO.description = "foo";
                providers.team = {
                  uri = "onepassword://Prod";
                  credentials.service_account_token = {
                    provider = "file:/etc/secrets";
                    ref.item = "service_account_token";
                  };
                };
              };
            }
          ];
        };
        cred = evaluated.config.secretspec.providers.team.credentials.service_account_token;
      in
      cred.provider == "file:/etc/secrets"
      && cred.ref.item == "service_account_token"
      && cred.ref.field == null;
  };

  # --- extension wiring (substrate-side) ---

  # Contributions are module functions (they bind the provider helpers), not paths.
  contributesNixosModule = {
    check = builtins.length contributed == 1 && builtins.isFunction (builtins.head contributed);
  };

  contributesHomeManagerModule = {
    check =
      builtins.length contributedUsers == 1 && builtins.isFunction (builtins.head contributedUsers);
  };

  # --- wrap backend (registered when the wrappers extension is loaded) ---

  noBackendWithoutWrappers = {
    check = !(eval.config.substrate.settings ? wrappers);
  };

  contributorRegistered = {
    check = wrapsEval.config.substrate.settings.wrappers.contributors ? secrets;
  };

  backendExecLineHostManifest = {
    check =
      let
        drv = wrapsArgs.wrap {
          package = fakePkg;
          secrets.scope = "github";
        };
        inherit (drv) body;
      in
      hasInfix ''exec -a "$0" /fake/secretspec/bin/secretspec run'' body
      && hasInfix "--file ${fakeStoreManifest}" body
      && hasInfix "--scope github" body
      && hasInfix "--caller substrate --caller-operation run" body
      # The invocation ends in `--` and the program. With nothing for a core to
      # carry (no args, no pre-hook) that is the program itself rather than a
      # second file in the output.
      && hasInfix ''-- /nix/store/hash-foo-1.0/bin/foo "$@"'' body
      && !(hasInfix ".foo-core" body);
  };

  # With something for the core to carry, the stub execs a hidden makeWrapper'd
  # program, and the args land there -- so "$VAR" expands after secretspec has run.
  backendArgsLandInTheCore = {
    check =
      let
        drv = wrapsArgs.wrap {
          package = fakePkg;
          secrets.scope = "github";
          args = [
            "--greeting"
            "$GREETING"
          ];
        };
        inherit (drv) body;
      in
      hasInfix ''-- @out@/bin/.foo-core "$@"'' body
      && hasInfix ''makeWrapper /nix/store/hash-foo-1.0/bin/foo "$out/bin/.foo-core"'' body
      && hasInfix "--add-flags" body
      && hasInfix "$GREETING" body;
  };

  # The manifest is rendered from the configuration the wrapper is built for, so
  # a spec names only its scope. Same content, same name, so it is the store file
  # the class module wrote.
  backendManifestRenderedFromConfiguration = {
    check =
      let
        drv = wrapsArgs.wrap {
          package = fakePkg;
          secrets.scope = "github";
        };
      in
      hasInfix "--file ${fakeStoreManifest}" drv.body;
  };

  # A target configuration that declares no secretspec has no manifest to render,
  # so the failure names the extension's class module rather than a path.
  backendRejectsTargetWithoutSecretspec = {
    check = throws (
      noSecretsArgs.wrap {
        package = fakePkg;
        secrets.scope = "github";
      }
    );
  };

  # An undeclared scope fails at eval time, in the configuration that should have
  # declared it, rather than at exec time wherever the wrapper happens to run.
  backendRejectsUndeclaredScope = {
    check = throws (
      noScopesArgs.wrap {
        package = fakePkg;
        secrets.scope = "github";
      }
    );
  };

  backendManifestOverride = {
    check =
      let
        drv = wrapsArgs.wrap {
          package = fakePkg;
          secrets.scope = "github";
          secrets.manifest = "/custom/secretspec.toml";
        };
        inherit (drv) body;
      in
      hasInfix "--file /custom/secretspec.toml" body;
  };

  backendCustomReason = {
    check =
      let
        reason = ''deploy "now"'';
        drv = wrapsArgs.wrap {
          package = fakePkg;
          secrets.scope = "github";
          secrets.reason = reason;
        };
        inherit (drv) body;
      in
      hasInfix ("--reason " + lib.escapeShellArg reason) body;
  };

  backendRejectsMissingPackage = {
    check = throws (wrapsArgs.wrap { secrets.scope = "github"; });
  };

  # A field neither the core vocabulary nor the contributor declares is an
  # error, never a silently ignored key.
  backendRejectsUnknownKeys = {
    check = throws (
      wrapsArgs.wrap {
        package = fakePkg;
        secrets.scope = "github";
        nope = "x";
      }
    );
  };

  # scope/reason/manifest are the contributor's own options, namespaced under
  # its key. The wrapper language around them belongs to the spec, not to the
  # contributor: `secrets.env` is a field nobody declared.
  backendRejectsTheWrapperLanguage = {
    check = throws (
      wrapsArgs.wrap {
        package = fakePkg;
        secrets.scope = "github";
        secrets.env.GREET = "hi";
      }
    );
  };

  # One wrapper carries both the invocation and the provider CLIs, and the spec's
  # own env and args with it — there is no second layer to nest.
  backendCarriesTheInvocationAndProviderPath = {
    check =
      let
        flat = packagesWrapsArgs.wrap {
          package = fakePkg;
          env.GREET = "hi";
          args = [ "--inner" ];
          secrets.scope = "github";
        };
      in
      hasInfix "secretspec run --file" flat.body
      && hasInfix ''PATH="/nix/store/hash-op-2.32.0/bin:$PATH"'' flat.body
      && hasInfix "export GREET=hi" flat.body
      && hasInfix "--add-flags ${lib.escapeShellArg "--inner"}" flat.body
      && flat.passthru.wrapped.outPath == fakePkg.outPath;
  };

  # --- entries.<name>.file materialization ---

  fileDefaultPathUnderVarLib = {
    check = nixEval.config.secretspec.entries.FOO.file.path == "/var/lib/secretspec/files/FOO";
  };

  fileDefaultOwnership = {
    check =
      let
        f = nixEval.config.secretspec.entries.FOO.file;
      in
      f.fileOwner == "root" && f.fileGroup == "root" && f.mode == "0600";
  };

  fileDefaultsToNullForEnvEntries = {
    check = nixEval.config.secretspec.entries.BAR.file == null;
  };

  hmFileDefaultUnderStateHome = {
    check =
      let
        f = hmEval.config.secretspec.entries.GITHUB_TOKEN.file;
      in
      f.path == "/home/craig/.local/state/secretspec/files/GITHUB_TOKEN"
      && f.fileOwner == "craig"
      && f.fileGroup == "users"
      && f.mode == "0600";
  };

  nixosMaterializerServiceGenerated = {
    check =
      let
        service = unwrap nixEval.config.systemd.services.secretspec-materialize;
      in
      service.serviceConfig.Type == "oneshot"
      && hasInfix "secretspec-materialize-files" service.serviceConfig.ExecStart
      # the store path, since manifestPath is null
      && builtins.any (
        e: lib.hasPrefix "SECRETSPEC_FILE=${fakeStoreManifest}" e
      ) service.serviceConfig.Environment;
  };

  # A systemd system unit has no HOME, and secretspec refuses to resolve
  # anything without an XDG config directory, so the unit supplies one.
  nixosMaterializerSuppliesXdgDirs = {
    check =
      let
        environment =
          (unwrap nixEval.config.systemd.services.secretspec-materialize).serviceConfig.Environment;
      in
      builtins.elem "XDG_CONFIG_HOME=/var/lib" environment
      && builtins.elem "XDG_STATE_HOME=/var/lib" environment;
  };

  nixosMaterializerCreatesXdgDirs = {
    check =
      let
        rules = unwrap nixEval.config.systemd.tmpfiles.rules;
      in
      builtins.elem "d /var/lib/secretspec 0700 root root -" rules;
  };

  materializerFetchesAndInstalls = {
    check =
      let
        text = (unwrap nixEval.config.systemd.services.secretspec-materialize).serviceConfig.ExecStart;
      in
      hasInfix "secretspec get FOO --file ${fakeStoreManifest}" text
      && hasInfix "install -D" text
      && hasInfix "-m 0600" text;
  };

  noMaterializerWithoutFileEntries = {
    check =
      let
        eval = lib.evalModules {
          modules = [
            (import ../../extensions/secrets/nixos-module.nix { inherit lib; })
            {
              options.networking.hostName = lib.mkOption { type = lib.types.str; };
              options.environment.etc = lib.mkOption { type = lib.types.raw; };
              options.environment.systemPackages = lib.mkOption { type = lib.types.raw; };
              options.systemd.services = lib.mkOption { type = lib.types.raw; };
              options.systemd.tmpfiles = lib.mkOption {
                type = lib.types.submodule (_: {
                  options.rules = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                  };
                });
                default = { };
              };
              config.secretspec.entries.BAR = {
                description = "bar";
                ref.item = "y";
              };
            }
          ];
          specialArgs = {
            pkgs = fakePkgs;
          };
        };

        svc = (unwrap eval.config.systemd.services).secretspec-materialize or null;
      in
      svc == null || (svc._type or "" == "if" && !svc.condition);
  };

  hmMaterializerUserUnitGenerated = {
    check =
      let
        unit = unwrap hmEval.config.systemd.user.services.secretspec-materialize;
        exec = unit.Service.ExecStart;
      in
      unit.Service.Type == "oneshot"
      && unit.Install.WantedBy == [ "default.target" ]
      && hmEval.config.systemd.user.startServices == "sdSwitch"
      && hasInfix "secretspec get GITHUB_TOKEN" exec
      # the manifest's store path
      && hasInfix "--file ${fakeStoreManifest}" exec
      && hasInfix "install -D" exec;
  };

  # --- secretspec.manifestPath ---

  # null: the manifest is read straight from the store, so there is nothing on
  # disk at all - no /etc entry, no config file, no symlink.
  nixosManifestDefaultIsTheStorePath = {
    check =
      let
        etc = unwrap nixEval.config.environment.etc;
        rules = unwrap nixEval.config.systemd.tmpfiles.rules;
        service = unwrap nixEval.config.systemd.services.secretspec-materialize;
      in
      !(etc ? "secretspec.toml")
      && !(builtins.any (r: lib.hasInfix "secretspec.toml" r) rules)
      && builtins.any (
        e: lib.hasPrefix "SECRETSPEC_FILE=${fakeStoreManifest}" e
      ) service.serviceConfig.Environment
      && hasInfix "secretspec get FOO --file ${fakeStoreManifest}" service.serviceConfig.ExecStart;
  };

  hmManifestDefaultIsTheStorePath = {
    check =
      let
        configFile = unwrap hmEval.config.xdg.configFile;
      in
      !(configFile ? "secretspec/secretspec.toml")
      && (unwrap hmEval.config.systemd.user.tmpfiles.rules) == [ ]
      && hmEval.config.home.sessionVariables.SECRETSPEC_FILE == fakeStoreManifest;
  };

  # A path under /etc is honored like any other: one symlink, no environment.etc.
  nixosManifestEtcPathUsesTmpfiles = {
    check =
      let
        path = "/etc/secrets.toml";
        etc = unwrap nixEtcNameEval.config.environment.etc;
        rules = unwrap nixEtcNameEval.config.systemd.tmpfiles.rules;
      in
      !(etc ? "secrets.toml")
      && !(etc ? "secretspec.toml")
      && builtins.elem "d /etc 0755 - - -" rules
      && builtins.elem "L+ ${path} - - - - ${fakeStoreManifest}" rules
      && builtins.elem "SECRETSPEC_FILE=${path}" (unwrap nixEtcNameEval.config.systemd.services.secretspec-materialize)
      .serviceConfig.Environment;
  };

  # Anywhere else behaves identically, and every consumer follows the one path.
  nixosManifestOutsideEtcUsesTmpfiles = {
    check =
      let
        path = "/var/lib/secrets/secretspec.toml";
        service = unwrap nixOutsideEtcEval.config.systemd.services.secretspec-materialize;
        rules = unwrap nixOutsideEtcEval.config.systemd.tmpfiles.rules;
      in
      builtins.elem "d /var/lib/secrets 0755 - - -" rules
      && builtins.elem "L+ ${path} - - - - ${fakeStoreManifest}" rules
      && builtins.elem "SECRETSPEC_FILE=${path}" service.serviceConfig.Environment
      && hasInfix "secretspec get FOO --file ${path}" service.serviceConfig.ExecStart;
  };

  # Inside the config home too: the same route, no xdg.configFile special case.
  hmManifestInsideHomeUsesTmpfiles = {
    check =
      let
        path = "/home/craig/.config/secrets/secretspec.toml";
      in
      !(unwrap hmInHomeEval.config.xdg.configFile ? "secrets/secretspec.toml")
      && builtins.elem "L+ ${path} - - - - ${fakeStoreManifest}" (
        unwrap hmInHomeEval.config.systemd.user.tmpfiles.rules
      )
      && hmInHomeEval.config.home.sessionVariables.SECRETSPEC_FILE == path;
  };

  hmManifestOutsideHomeUsesTmpfiles = {
    check =
      let
        path = "/home/craig/.local/state/secrets/secretspec.toml";
        unit = unwrap hmOutsideHomeEval.config.systemd.user.services.secretspec-materialize;
        rules = unwrap hmOutsideHomeEval.config.systemd.user.tmpfiles.rules;
      in
      builtins.elem "d /home/craig/.local/state/secrets 0755 - - -" rules
      && builtins.elem "L+ ${path} - - - - ${fakeStoreManifest}" rules
      && builtins.elem "SECRETSPEC_FILE=${path}" unit.Service.Environment
      && hasInfix "--file ${path}" unit.Service.ExecStart;
  };

  # A class module defaults the project from the class's own identity, so the
  # manifest render is a pure function of the secretspec options and a wrapper
  # anywhere in that configuration reproduces the same store path.
  nixosClassModuleDefaultsProject = {
    check = nixEval.config.secretspec.project == "hosts";
  };

  hmClassModuleDefaultsProject = {
    check = hmEval.config.secretspec.project == "craig";
  };

  # Nothing publishes the manifest or the scopes back into substrate settings
  # any more: a class module declaring no substrate options at all is the case
  # that used to fail with "option 'substrate' does not exist".
  classModulesDeclareNoSubstrateOptions = {
    check =
      !(nixEval.config ? substrate)
      && !(hmEval.config ? substrate)
      && !builtins.elem "substrate" (builtins.attrNames nixEval.config);
  };

  asPathWithFileThrows = {
    check = throws (
      builtins.deepSeq nixEval.config
        (lib.evalModules {
          modules = [
            (import ../../extensions/secrets/nixos-module.nix { inherit lib; })
            {
              options.networking.hostName = lib.mkOption {
                type = lib.types.str;
                default = "h";
              };
              options.environment.etc = lib.mkOption { type = lib.types.raw; };
              options.environment.systemPackages = lib.mkOption { type = lib.types.raw; };
              options.systemd.services = lib.mkOption { type = lib.types.raw; };
              config.secretspec.entries.FOO = {
                asPath = true;
                file = { };
              };
            }
          ];
          specialArgs = {
            pkgs = fakePkgs;
          };
        }).config
    );
  };

  noHomeManagerModulesWithoutHm = {
    check = !(eval.config.substrate.settings ? homeManagerModules);
  };

  # --- provider CLIs (secretspec.providers.<alias>.package) ---

  contributedModuleEvaluates = {
    check =
      let
        nixosService = unwrap contributedNixosEval.config.systemd.services.secretspec-materialize;
        hmUnit = unwrap contributedHmEval.config.systemd.user.services.secretspec-materialize;
      in
      nixosService.serviceConfig.Type == "oneshot" && hmUnit.Service.Type == "oneshot";
  };

  # A wrapper's PATH carries the CLIs of the providers its scope can reach, taken
  # from the configuration it is built for — so they come from that host's package
  # set rather than from anything resolved in substrate's own evaluation.
  providerPackagesInWrapStub = {
    check =
      hasInfix ''PATH="/nix/store/hash-op-2.32.0/bin:$PATH"''
        (packagesWrapsArgs.wrap {
          package = fakePkg;
          secrets.scope = "github";
        }).body;
  };

  # A provider that declares no CLI contributes none: `keyring://` is built in,
  # and a provider whose CLI is already on the caller's PATH needs nothing.
  providerWithoutAPackageContributesNoPath = {
    check =
      let
        noPackages = wrapsArgsFor {
          substrateEval = wrapsEval;
          target = noProviderPackageTarget;
        };
      in
      !(hasInfix "PATH="
        (noPackages.wrap {
          package = fakePkg;
          secrets.scope = "github";
        }).body
      );
  };

  # A provider's package never reaches the manifest: the manifest holds
  # declarations, and a derivation path would be neither.
  providerPackageIsNotRendered = {
    check =
      !(hasInfix "hash-op" (render {
        project = "h";
        entries = {
          FOO = {
            description = "foo";
            default = "x";
          };
        };
        providers = {
          op = {
            uri = "onepassword://Infra";
            package = "/nix/store/hash-op-2.32.0";
          };
        };
      }));
  };

  # A wrapped command run by a system unit has no HOME either; the stub defaults
  # an XDG root only in that case, so a session keeps its own.
  wrapStubDefaultsXdgRootForHostBuild = {
    check =
      let
        inherit
          (
            (packagesWrapsArgs.wrap {
              package = fakePkg;
              secrets.scope = "github";
            })
          )
          body
          ;
      in
      hasInfix ''if [[ -z "''${HOME:-}" && -z "''${XDG_CONFIG_HOME:-}" ]]; then'' body
      && hasInfix ''export XDG_CONFIG_HOME="/var/lib"'' body
      && hasInfix ''export XDG_STATE_HOME="/var/lib"'' body;
  };

  # User builds run with a HOME, so they get no fallback at all: an unexpected
  # missing HOME should fail with secretspec's own error rather than relocate a
  # provider CLI's state to a guessed path.
  userBuildStubHasNoXdgFallback = {
    check =
      let
        inherit
          (
            (
              (wrapsArgsFor {
                substrateEval = packagesWrapsEval;
                usercfg = {
                  name = "u";
                };
              }).wrap
                {
                  package = fakePkg;
                  secrets.scope = "github";
                }
            )
          )
          body
          ;
      in
      !(hasInfix "export XDG_CONFIG_HOME" body) && !(hasInfix "export XDG_STATE_HOME" body);
  };

  # A configuration with no provider at all: nothing to put on the PATH, and the
  # invocation is unchanged.
  noWrapStubPathWithoutProviders = {
    check =
      let
        # A scope, but no provider declaring a CLI: the invocation is unchanged
        # and nothing joins the PATH.
        bare = wrapsArgsFor {
          substrateEval = wrapsEval;
          target = lib.recursiveUpdate nixosStubs {
            config.secretspec.scopes.github.secrets = [ "FOO" ];
          };
        };
      in
      !(hasInfix "PATH="
        (bare.wrap {
          package = fakePkg;
          secrets.scope = "github";
        }).body
      )
      &&
        hasInfix "secretspec run"
          (bare.wrap {
            package = fakePkg;
            secrets.scope = "github";
          }).body;
  };

  providerPackagesInNixosMaterializer = {
    check = hasInfix ":/nix/store/hash-op-2.32.0/bin" (unwrap packagesNixosEval.config.systemd.services.secretspec-materialize)
    .serviceConfig.ExecStart;
  };

  providerPackagesInHmMaterializer = {
    check = hasInfix ":/nix/store/hash-op-2.32.0/bin" (unwrap packagesHmEval.config.systemd.user.services.secretspec-materialize)
    .Service.ExecStart;
  };
}
