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
    writeShellScript = name: text: "script:${text}";
    writeText = name: text: "text:${name}:${text}";
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

  # Option stubs and declarations for a NixOS-class eval, shared by the direct
  # class-module tests and the contributed-module tests so both drive the same
  # configuration.
  nixosStubs = {
    options.networking.hostName = lib.mkOption {
      type = lib.types.str;
      default = "hosts";
    };
    options.environment.etc = lib.mkOption { type = lib.types.raw; };
    options.environment.systemPackages = lib.mkOption { type = lib.types.raw; };
    options.systemd.services = lib.mkOption { type = lib.types.raw; };
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
    options.systemd.user.startServices = lib.mkOption {
      type = lib.types.raw;
      default = "no";
    };
    options.xdg.configHome = lib.mkOption {
      type = lib.types.str;
      default = "/home/craig/.config";
    };
    options.xdg.configFile = lib.mkOption { type = lib.types.raw; };
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

  eval = evalSubstrate [ ../../extensions/secrets/default.nix ];

  wrapsEval = evalSubstrate [
    ../../extensions/wrappers/default.nix
    ../../extensions/secrets/default.nix
  ];

  # Same extensions, but with the CLIs providers shell out to declared as a
  # function of the configuration's pkgs, reachable only through them.
  packagesWrapsEval = evalSubstrate [
    ../../extensions/wrappers/default.nix
    ../../extensions/secrets/default.nix
    {
      substrate.settings.secrets.providerPackages = pkgs: [ pkgs._1password-cli ];
    }
  ];

  wrapsArgsFor =
    eval': usercfg:
    eval'.config.substrate.lib.extraArgsGenerator {
      hostcfg = {
        name = "h";
      };
      inherit usercfg;
      inputs = { };
      pkgs = fakePkgs;
    };

  wrapsArgs = wrapsArgsFor wrapsEval;

  packagesWrapsArgs = wrapsArgsFor packagesWrapsEval;

  contributed = eval.config.substrate.lib.contributionsFor "nixos" { };
  contributedUsers = eval.config.substrate.lib.contributionsFor "homeManager" { };

  # The contributed modules as the builder loads them, so the injection of
  # providerPackages is exercised through the real contribution path.
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

  # Same, with the provider CLIs declared.
  packagesEval = evalSubstrate [
    ../../extensions/secrets/default.nix
    {
      substrate.settings.secrets.providerPackages = pkgs: [ pkgs._1password-cli ];
    }
  ];

  packagesNixosEval = lib.evalModules {
    modules = packagesEval.config.substrate.lib.contributionsFor "nixos" { } ++ [ nixosStubs ];
    specialArgs = {
      pkgs = fakePkgs;
    };
  };

  packagesHmEval = lib.evalModules {
    modules = packagesEval.config.substrate.lib.contributionsFor "homeManager" { } ++ [ hmStubs ];
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

  # Contributions are module functions (they inject providerPackages), not paths.
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

  backendRegistered = {
    check = (wrapsArgs null).wrap ? withSecret;
  };

  backendExecLineHostManifest = {
    check =
      let
        drv = (wrapsArgs null).wrap.withSecret {
          package = fakePkg;
          scope = "github";
        };
        body = drv.body;
      in
      hasInfix ''exec -a "$0" /fake/secretspec/bin/secretspec run'' body
      && hasInfix ''--file "/etc/secretspec.toml"'' body
      && hasInfix "--scope github" body
      && hasInfix "--caller substrate --caller-operation run" body
      && hasInfix ''-- @out@/bin/.foo-core "$@"'' body
      && hasInfix ''makeWrapper /nix/store/hash-foo-1.0/bin/foo "$out/bin/.foo-core" --inherit-argv0'' body;
  };

  backendManifestFromUserBuild = {
    check =
      let
        drv = (wrapsArgs { name = "u"; }).wrap.withSecret {
          package = fakePkg;
          scope = "github";
        };
        body = drv.body;
      in
      hasInfix ''--file "''${XDG_CONFIG_HOME:-$HOME/.config}/secretspec/secretspec.toml"'' body;
  };

  backendManifestOverride = {
    check =
      let
        drv = (wrapsArgs null).wrap.withSecret {
          package = fakePkg;
          scope = "github";
          manifest = "/custom/secretspec.toml";
        };
        body = drv.body;
      in
      hasInfix ''--file "/custom/secretspec.toml"'' body;
  };

  backendCustomReason = {
    check =
      let
        reason = ''deploy "now"'';
        drv = (wrapsArgs null).wrap.withSecret {
          package = fakePkg;
          scope = "github";
          inherit reason;
        };
        body = drv.body;
      in
      hasInfix ("--reason " + lib.escapeShellArg reason) body;
  };

  backendRejectsMissingPackage = {
    check = throws ((wrapsArgs null).wrap.withSecret { scope = "github"; });
  };

  backendRejectsUnknownKeys = {
    check = throws (
      (wrapsArgs null).wrap.withSecret {
        package = fakePkg;
        scope = "github";
        env.NOPE = "x";
      }
    );
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
      && service.serviceConfig.Environment == [ "SECRETSPEC_FILE=/etc/secretspec.toml" ];
  };

  materializerFetchesAndInstalls = {
    check =
      let
        text = (unwrap nixEval.config.systemd.services.secretspec-materialize).serviceConfig.ExecStart;
      in
      hasInfix "secretspec get FOO --file /etc/secretspec.toml" text
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
              config.secretspec.entries.BAR.ref.item = "y";
            }
          ];
          specialArgs = {
            pkgs = fakePkgs;
          };
        };
      in
      let
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
      && hasInfix ''--file "${
        lib.concatStringsSep "" [
          "$"
          "{XDG_CONFIG_HOME:-\$HOME/.config}/secretspec/secretspec.toml"
        ]
      }"'' exec
      && hasInfix "install -D" exec;
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

  # --- provider CLIs (substrate.settings.secrets.providerPackages) ---

  contributedModuleEvaluates = {
    check =
      let
        nixosService = unwrap contributedNixosEval.config.systemd.services.secretspec-materialize;
        hmUnit = unwrap contributedHmEval.config.systemd.user.services.secretspec-materialize;
      in
      nixosService.serviceConfig.Type == "oneshot" && hmUnit.Service.Type == "oneshot";
  };

  # The paths come from the pkgs the wrap build ran with, not from anything
  # resolved in substrate's own evaluation.
  providerPackagesInWrapStub = {
    check =
      hasInfix ''PATH="/nix/store/hash-op-2.32.0/bin:$PATH"''
        ((packagesWrapsArgs null).wrap.withSecret {
          package = fakePkg;
          scope = "github";
        }).body;
  };

  noWrapStubPathWithoutProviderPackages = {
    check =
      !(hasInfix "PATH="
        ((wrapsArgs null).wrap.withSecret {
          package = fakePkg;
          scope = "github";
        }).body
      );
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
