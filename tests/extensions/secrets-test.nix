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
    paths
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

  throws = expr: !(builtins.tryEval expr).success;

  optionsEval = lib.evalModules {
    modules = [
      ../../extensions/secrets/options.nix
      {
        config.substrate.secrets = {
          entries.GITHUB_TOKEN.description = "from module one";
          entries.API_KEY.required = false;
          providers.team.uri = "onepassword://Prod";
        };
      }
      {
        config.substrate.secrets = {
          entries.CA_BUNDLE.asPath = true;
          providers.team.credentials.service_account_token = "env";
          providers.local.uri = "keyring://";
          scopes.api.secrets = [ "GITHUB_TOKEN" ];
          defaultProviders = [ "team" ];
        };
      }
    ];
  };

  fakePkgs = {
    secretspec = "/fake/secretspec";
  };

  eval = evalSubstrate [ ../../extensions/secrets/default.nix ];

  moduleArgsFor =
    hostcfg:
    eval.config.substrate.lib.extraArgsGenerator {
      inherit hostcfg;
      usercfg = null;
      inputs = { };
      pkgs = fakePkgs;
    };

  hostArgs = moduleArgsFor { name = "unsouled"; };
  userArgs = moduleArgsFor null;

  contributed = builtins.head eval.config.substrate.settings.perHostContributors { };
  contributedUsers = builtins.head eval.config.substrate.settings.perUserContributors { };
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
        cfg = optionsEval.config.substrate.secrets;
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
        cfg = optionsEval.config.substrate.secrets;
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

  helperOnlyForHostBuilds = {
    check = hostArgs ? secrets && !(userArgs ? secrets);
  };

  helperRunString = {
    check =
      let
        run = hostArgs.secrets.run {
          scope = "github";
          cmd = "/bin/srv serve";
        };
      in
      hasInfix "@${fakePkgs.secretspec}/bin/secretspec run" run
      && hasInfix "--file ${paths.nixosManifest}" run
      && hasInfix "--scope github" run
      && hasInfix "--caller substrate" run
      && hasInfix "-- /bin/srv serve" run;
  };

  helperRunCustomReason = {
    check =
      let
        reason = ''deploy "now"'';
      in
      hasInfix ("--reason " + lib.escapeShellArg reason) (
        hostArgs.secrets.run {
          scope = "github";
          cmd = "/bin/srv";
          inherit reason;
        }
      );
  };

  noHomeManagerModulesWithoutHm = {
    check = !(eval.config.substrate.settings ? homeManagerModules);
  };

  contributesHomeManagerModule = {
    check = contributedUsers == [ ../../extensions/secrets/home-manager-module.nix ];
  };
}
