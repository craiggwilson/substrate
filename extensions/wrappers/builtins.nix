# The three built-in backends, named by the mechanism nixpkgs itself uses:
#
#   shell    in-place tree + makeWrapper (shell stub) — the default
#   binary   in-place tree + makeBinaryWrapper (compiled stub)
#   script   standalone single-script package (text wrappers, exec prefixes,
#            renaming, post hooks)
#
# Each is a pair of (option module, build function); the wrap pipeline
# evaluates them exactly like contributed backends. `toScript`, `toOuter`, and
# `toStubFlags` are the pure text builders, exposed for tests and inspection.
# The in-place shell and script backends share makeWrapper as the stub engine.
{
  lib,
  pkgs,
  common,
}:
let
  inherit (common)
    resolveFns
    fileLinks
    aliasLinks
    fileType
    ;

  filesType = fileType pkgs;

  ## shared option groups (each is a module body)

  filesOptions = {
    options.files = lib.mkOption {
      type = lib.types.attrsOf filesType;
      default = { };
      example."mpv.conf".text = "vo=gpu\n";
      description = ''
        Files materialized into the wrapper output at $out/<attr path>,
        verbatim. Reference their resolved paths from env/args via a function
        receiving the files attrset, or from a typed definition's spec via
        config.files.<name>.path.
      '';
    };

    options.aliases = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = "Additional names symlinked to the wrapped executable.";
    };

    options.exe = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      example = "ls";
      description = ''
        Which binary under bin/ to wrap, when meta.mainProgram is absent or
        not the program you want (e.g. bin/ls in coreutils).
      '';
    };
  };

  stubOptions = {
    options.env = lib.mkOption {
      type =
        with lib.types;
        attrsOf (oneOf [
          raw
          (functionTo raw)
        ]);
      default = { };
      description = "Environment variables to export (values string-coerced; a function value receives the files attrset).";
    };

    options.args = lib.mkOption {
      type = with lib.types; listOf raw;
      default = [ ];
      description = ''CLI arguments inserted before "$@" (shell-escaped verbatim).'';
    };

    options.runtimeInputs = lib.mkOption {
      type = with lib.types; listOf package;
      default = [ ];
      description = "Packages added to the wrapper's PATH.";
    };
  };

  requiresPackage =
    name:
    { config, ... }:
    {
      config.assertions = [
        {
          assertion = config.package != null;
          message = "${name} requires { package = ... }.";
        }
      ];
    };

  binNameOf = cfg: if cfg.exe != null then cfg.exe else baseNameOf (lib.getExe cfg.package);

  ## in-place backends (shell or compiled stub over a copied tree)

  toStubFlags =
    cfg:
    lib.concatStringsSep " " (
      builtins.map lib.escapeShellArg (
        [ ]
        ++ lib.concatLists (
          lib.mapAttrsToList (n: v: [
            "--set"
            n
            (toString v)
          ]) (cfg.env or { })
        )
        ++ lib.optionals (cfg.args or [ ] != [ ]) [
          "--add-flags"
          (lib.escapeShellArgs cfg.args)
        ]
        ++ lib.optionals (cfg.runtimeInputs or [ ] != [ ]) [
          "--prefix"
          "PATH"
          ":"
          (lib.makeBinPath cfg.runtimeInputs)
        ]
        ++ lib.optionals (cfg.preHook or "" != "") [
          "--run"
          cfg.preHook
        ]
      )
    );

  # symlinkJoin (lndir) makes real directories of symlinked files into the
  # immutable original, so the applications/ subtree is replaced — with
  # patched regular files — and only when there are entries to patch.
  desktopPatch = package: ''
    if [ -e "${package}/share/applications" ]; then
      if find "${package}/share/applications" -name "*.desktop" -type f | read -r _; then
        rm -rf "$out/share/applications"
        mkdir -p "$out/share/applications"
        (
          cd "${package}/share/applications"
          find . -name "*.desktop" -type f | while read -r f; do
            d="$out/share/applications/$(dirname "$f")"
            mkdir -p "$d"
            sed "s|${package}|$out|g" "$f" > "$d/$(basename "$f")"
          done
        )
      fi
    fi
  '';

  buildInplace =
    {
      stubCommand,
      stubPackage,
      suffix,
    }:
    ctx: cfg0:
    let
      cfg = resolveFns cfg0;
      binName = binNameOf cfg;
      treeLinks = builtins.concatStringsSep "\n" (fileLinks cfg.files ++ aliasLinks binName cfg.aliases);
    in
    pkgs.symlinkJoin {
      name = "${lib.getName cfg.package}${suffix}";
      paths = [ cfg.package ];
      meta = (cfg.package.meta or { }) // {
        mainProgram = binName;
      };
      # makeBinaryWrapper self-contains its compiler reference.
      nativeBuildInputs = [ stubPackage ];
      postBuild = ''
        ${stubCommand} "$out/bin/${binName}" ${toStubFlags cfg}
        ${desktopPatch cfg.package}
        ${treeLinks}
        ${cfg.postBuildHook or ""}
      '';
    };

  shellModule = {
    imports = [
      filesOptions
      stubOptions
      (requiresPackage "wrap.withShell")
    ];
    options.preHook = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Shell run before the program starts (via makeWrapper --run).";
    };
    options.postBuildHook = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Shell appended to the in-place build, after the stub, desktop patch, and links.";
    };
  };

  binaryModule = {
    imports = [
      filesOptions
      stubOptions
      (requiresPackage "wrap.withBinary")
    ];
  };

  ## standalone script backend
  ##
  ## Package mode delegates to makeWrapper itself (standalone mode of the
  ## low-level hook: it writes a hardened script — argv0 inheritance, PATH
  ## dedup, flag assembly — at any path). Only the features makeWrapper
  ## cannot express are hand-rolled: a thin outer layer when `prefix` or
  ## `postHook` is set (core script hidden as .<name>-core), and the raw
  ## script body in text (cmd) mode, which has no executable to point at.

  envExportLines =
    env:
    lib.mapAttrsToList (
      n: v:
      if builtins.match "^[A-Za-z_][A-Za-z0-9_]*$" n != null then
        "export ${n}=${lib.escapeShellArg (toString v)}"
      else
        throw "substrate(wrappers): invalid env var name '${n}'."
    ) env;

  # Text (cmd) mode body: preHook, exports, PATH, then the caller's script.
  toScript =
    cfg:
    lib.concatStringsSep "\n" (
      lib.filter (s: s != "") (
        [ cfg.preHook or "" ]
        ++ envExportLines (cfg.env or { })
        ++ lib.optionals (cfg.runtimeInputs or [ ] != [ ]) [
          ''PATH="${lib.makeBinPath cfg.runtimeInputs}:$PATH"''
        ]
        ++ [ cfg.cmd ]
      )
    );

  # Thin outer script for the layered package case. `@out@` is replaced with
  # the final output path in the builder; "$0"/"$@" are runtime literals.
  toOuter =
    {
      binName,
      prefix ? [ ],
      postHook ? "",
    }:
    let
      core = "@out@/bin/.${binName}-core";
      launch = lib.concatStringsSep " " (prefix ++ [ core ]);
    in
    if postHook != "" then
      ''
        ( exec -a "$0" ${launch} "$@" )
        code=$?
        ${postHook}
        exit $code
      ''
    else
      ''exec -a "$0" ${launch} "$@"'';

  scriptModule =
    { config, ... }:
    {
      imports = [
        filesOptions
        stubOptions
      ];
      options = {
        prefix = lib.mkOption {
          type = with lib.types; listOf raw;
          default = [ ];
          example = [ "uwsm app --" ];
          description = "Raw command fragments placed before the wrapped exe (launchers, secrets runners).";
        };
        name = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          description = "Name of the wrapped command; required in text (cmd) mode, renames the exe otherwise.";
        };
        cmd = lib.mkOption {
          type = with lib.types; nullOr lines;
          default = null;
          description = "Whole script body instead of wrapping a package; the text-launcher escape hatch.";
        };
        preHook = lib.mkOption {
          type = lib.types.lines;
          default = "";
        };
        postHook = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Runs after the program (disables exec; the program's exit code propagates).";
        };
      };
      config.assertions = [
        {
          assertion = config.cmd == null || config.package == null;
          message = "wrap.withScript takes exactly one of { package, cmd }, not both.";
        }
        {
          assertion = config.cmd == null || config.name != null;
          message = "wrap.withScript text mode (cmd) requires { name = ... }.";
        }
        {
          assertion = config.cmd == null || (config.args == [ ] && config.prefix == [ ]);
          message = "wrap.withScript: args and prefix apply to package mode; put that text in cmd.";
        }
      ];
    };

  scriptBuild =
    ctx: cfg0:
    let
      cfg = resolveFns cfg0;
      binName = if cfg.name != null then cfg.name else binNameOf cfg;
      textMode = cfg.cmd != null;
      layered = !textMode && (cfg.prefix != [ ] || cfg.postHook != "");
      coreFlags = toStubFlags cfg;
      body =
        if textMode then
          ''cp ${pkgs.writeShellScript binName (toScript cfg)} "$out/bin/${binName}"''
        else if layered then
          ''
            makeWrapper ${lib.getExe cfg.package} "$out/bin/.${binName}-core" ${coreFlags} --inherit-argv0
            substitute ${
              pkgs.writeShellScript "${binName}-outer" (toOuter {
                inherit binName;
                prefix = cfg.prefix;
                postHook = cfg.postHook;
              })
            } "$out/bin/${binName}" --replace-fail "@out@" "$out"
          ''
        else
          ''makeWrapper ${lib.getExe cfg.package} "$out/bin/${binName}" ${coreFlags} --inherit-argv0'';
      treeLinks = builtins.concatStringsSep "\n" (fileLinks cfg.files ++ aliasLinks binName cfg.aliases);
    in
    pkgs.runCommand binName
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
        meta = (if cfg.package == null then { } else cfg.package.meta or { }) // {
          mainProgram = binName;
        };
      }
      ''
        mkdir -p $out/bin
        ${body}
        chmod +x "$out/bin/${binName}"
        ${treeLinks}
      '';
in
{
  inherit toScript toOuter toStubFlags;

  backends = {
    shell = {
      options = shellModule;
      build = buildInplace {
        stubCommand = "wrapProgram";
        stubPackage = pkgs.makeWrapper;
        suffix = "-wrapped";
      };
    };
    binary = {
      options = binaryModule;
      build = buildInplace {
        stubCommand = "makeBinaryWrapper";
        stubPackage = pkgs.makeBinaryWrapper;
        suffix = "-wrapped-binary";
      };
    };
    script = {
      options = scriptModule;
      build = scriptBuild;
    };
  };
}
