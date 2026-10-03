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
        description = "";
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
          service_account_token = "env";
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
          entries.API_KEY.required = false;
          providers.team.uri = "onepassword://Prod";
        };
      }
      {
        config.secretspec = {
          entries.CA_BUNDLE.asPath = true;
          providers.team.credentials.service_account_token = "env";
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

  fakePkgs = {
    secretspec = "/fake/secretspec";
    makeWrapper = "/fake/makeWrapper";
    coreutils = "/fake/coreutils";
    writeShellScript = name: text: "script:${text}";
    writeText = name: text: "text:${name}:${text}";
    writeShellApplication =
      { name, text, ... }:
      # outPath embeds the script text so ExecStart interpolations are inspectable.
      mkFakeDrv {
        inherit name text;
        outPath = "drv:" + text;
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

  nixEval = lib.evalModules {
    modules = [
      ../../extensions/secrets/nixos-module.nix
      {
        options.networking.hostName = lib.mkOption {
          type = lib.types.str;
          default = "hosts";
        };
        options.environment.etc = lib.mkOption { type = lib.types.raw; };
        options.environment.systemPackages = lib.mkOption { type = lib.types.raw; };
        options.systemd.services = lib.mkOption { type = lib.types.raw; };
        config.secretspec = {
          entries.FOO = {
            ref.item = "x";
            file = { };
          };
          entries.BAR.ref.item = "y";
        };
      }
    ];
    specialArgs = {
      pkgs = fakePkgs;
    };
  };

  hmEval = lib.evalModules {
    modules = [
      ../../extensions/secrets/home-manager-module.nix
      {
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
          ref.item = "x";
          file = { };
        };
      }
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

  wrapsArgs =
    usercfg:
    wrapsEval.config.substrate.lib.extraArgsGenerator {
      hostcfg = {
        name = "h";
      };
      inherit usercfg;
      inputs = { };
      pkgs = fakePkgs;
    };

  contributed = eval.config.substrate.lib.contributionsFor "nixos" { };
  contributedUsers = eval.config.substrate.lib.contributionsFor "homeManager" { };
in
runTests "Secrets Extension Tests" {
  # --- manifest rendering (pure) ---

  renderProjectHeader = {
    check = lib.strings.hasPrefix ''
      [project]
      name = "unsouled"
    '' sampleRender;
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
    check = hasInfix "SESSION_PASSWORD = { prompt = true, required = false }" sampleRender;
  };

  renderProviderStringVsTable = {
    check =
      hasInfix ''local = "keyring://"'' sampleRender
      && hasInfix ''team = { credentials = { service_account_token = "env" }, uri = "onepassword://Prod" }'' sampleRender;
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
              ref = {
                vault = "Craig";
                item = "Github";
                field = "api_token";
              };
            };
            TOKENS = {
              composed = ''access-tokens = github.com=''${GITHUB_API_TOKEN}'';
              file = { };
            };
          };
        };
      in
      hasInfix ''GITHUB_API_TOKEN = { ref = { field = "api_token", item = "Github", vault = "Craig" } }'' out
      && hasInfix ''TOKENS = { composed = "access-tokens = github.com=''${GITHUB_API_TOKEN}" }'' out;
  };

  renderRejectsComposedWithRef = {
    check = throws (render {
      project = "p";
      entries.BAD = {
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
        composed = "x";
        providers = [ "p" ];
      };
    });
  };

  renderRejectsComposedWithDefault = {
    check = throws (render {
      project = "p";
      entries.BAD = {
        composed = "x";
        default = "y";
      };
    });
  };

  renderRejectsComposedWithAsPath = {
    check = throws (render {
      project = "p";
      entries.BAD = {
        composed = "x";
        asPath = true;
      };
    });
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
      entries.FOO = { };
      scopes.bad.secrets = [ "MISSING" ];
    });
  };

  rejectRefWithoutItem = {
    check = throws (render {
      project = "x";
      entries.FOO.ref = {
        item = "";
        field = "token";
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
      && cfg.providers.team.credentials.service_account_token == "env";
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
      && hasInfix "API_KEY = { required = false }" out;
  };

  # --- extension wiring (substrate-side) ---

  contributesNixosModule = {
    check = contributed == [ ../../extensions/secrets/nixos-module.nix ];
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
            ../../extensions/secrets/nixos-module.nix
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
      && unit.wantedBy == [ "default.target" ]
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
            ../../extensions/secrets/nixos-module.nix
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

  contributesHomeManagerModule = {
    check = contributedUsers == [ ../../extensions/secrets/home-manager-module.nix ];
  };
}
