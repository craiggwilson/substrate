# Shared machinery for the wrap pipeline: the core option vocabulary every spec is
# evaluated against, cross-field assertions, the file option type, the text
# helpers the stub shapes share, and passthru finalization. Stub rendering lives
# in stubs.nix; extensions add to a wrapper by registering a contributor in
# substrate.settings.wrappers.contributors (see wrap.nix) and get all of this
# for free.
{ lib, pkgs }:
let
  # One declarative file entry: text (written to the store), source (an
  # existing path/derivation), or an explicit path (which may be a shell
  # string like "$HOME/.config/app.conf" for runtime resolution).
  fileType =
    pkgs':
    lib.types.submodule (
      { name, config, ... }:
      {
        options = {
          text = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "File contents; written to the store as the file when set.";
          };

          source = lib.mkOption {
            type = with lib.types; nullOr (either path package);
            default = null;
            description = "An existing store path or derivation to use instead of generating from text.";
          };

          path = lib.mkOption {
            type = with lib.types; either path str;
            description = ''
              Resolved location of the file: `source` when set, otherwise the
              store path of `text`. May be overridden with a literal string to
              reference a runtime-computed path.
            '';
            default =
              if config.source != null then
                "${config.source}"
              else if config.text != "" then
                "${pkgs'.writeText name config.text}"
              else
                throw "substrate(wrappers): files.'${name}' sets neither text nor source.";
            defaultText = lib.literalExpression "source or writeText name text";
          };
        };
      }
    );

  # The stub that becomes the wrapper: a shell script (makeWrapper) or a compiled
  # one. A compiled stub cannot run an exec chain, so naming one alongside a
  # prefix, a setup snippet, or a contributor that supplies its own program is an
  # error rather than a silently ignored chain.
  stubShapes = {
    makeWrapper = {
      stubPackage = "makeWrapper";
      description = "a shell stub (makeWrapper)";
    };
    makeBinaryWrapper = {
      stubPackage = "makeBinaryWrapper";
      description = "a compiled stub (makeBinaryWrapper)";
    };
  };

  # Options every spec receives: passthru, and the internal cross-field assertion
  # sink.
  commonModule = {
    options.passthru = lib.mkOption {
      type = lib.types.attrsOf lib.types.raw;
      default = { };
      description = "Attributes to merge into the wrapper derivation's passthru.";
    };

    options.assertions = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            assertion = lib.mkOption {
              type = lib.types.bool;
              description = "Whether the check passed.";
            };
            message = lib.mkOption {
              type = lib.types.str;
              description = "Error shown when the assertion fails.";
            };
          };
        }
      );
      default = [ ];
      internal = true;
      description = "Cross-field rules contributed by option modules.";
    };
  };

  # The wrapper interface: what a spec can say about the wrapped program.
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
      example = [
        "--config"
        "$CONFIG_PATH"
      ];
      description = ''
        CLI arguments inserted before "$@". Entries are joined with spaces and
        interpolated verbatim into the wrapper's exec line, so shell constructs
        such as "$VAR" expand at exec time — after any contributor's chain has
        run. Pass an already-escaped string (`lib.escapeShellArgs [...]`) when a
        literal value is required.
      '';
    };

    options.runtimeInputs = lib.mkOption {
      type = with lib.types; listOf package;
      default = [ ];
      description = "Packages added to the wrapper's PATH.";
    };
  };

  # Same, for the files the output carries and the extra names linked to it.
  filesOptions = {
    options.files = lib.mkOption {
      type = lib.types.attrsOf (fileType pkgs);
      default = { };
      example."mpv.conf".text = "vo=gpu\n";
      description = ''
        Files materialized into the wrapper output at $out/<attr path>,
        verbatim. Reference their resolved paths from env/args via a function
        receiving the files attrset.
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

  # The whole core vocabulary, as one module. There is one wrapper per call, so
  # these fields are the entire interface: contributors add to them (see the
  # `prefix`/`runtimeInputs`/… hooks in wrap.nix) and none of them is ever
  # rendered by anything but the core.
  coreOptions =
    { config, ... }:
    {
      imports = [
        commonModule
        filesOptions
        stubOptions
      ];

      options = {
        package = lib.mkOption {
          type = lib.types.package;
          description = "The package to wrap: the executable it resolves to is the one that gets wrapped.";
        };

        stub = lib.mkOption {
          type = lib.types.enum (builtins.attrNames stubShapes);
          default = "makeWrapper";
          description = ''
            Which stub becomes the wrapper. `makeWrapper` writes a shell script,
            so anything may be composed around it. `makeBinaryWrapper` writes a
            compiled one, which cannot run an exec chain: pairing it with a
            `prefix`, a setup snippet, or a contributor that supplies a different
            program is an error.
          '';
        };

        name = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          description = "Rename the wrapped command; the executable it replaces is removed rather than left beside it.";
        };

        prefix = lib.mkOption {
          type = with lib.types; listOf raw;
          default = [ ];
          example = [ "uwsm app --" ];
          description = ''
            Raw exec-chain fragments between the program and any contributor's
            chain — launchers, session managers. Innermost, so a contributor can
            wrap the whole invocation.
          '';
        };

        preHook = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Shell run before the program starts (via makeWrapper --run).";
        };

        postHook = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = ''
            Runs after the program, with the program's exit code in `$?`. The
            wrapper's exec becomes a subshell so the code can be inspected, and
            the hook's own exit status does not replace the program's.
          '';
        };
      };
    };

  # One `export NAME=value` line per variable, rejecting names a shell cannot
  # assign. Both stub shapes that write their own script text use this so they
  # agree on the escaping and the failure message.
  envExportLines =
    env:
    lib.mapAttrsToList (
      n: v:
      if builtins.match "^[A-Za-z_][A-Za-z0-9_]*$" n != null then
        "export ${n}=${lib.escapeShellArg (toString v)}"
      else
        throw "substrate(wrappers): invalid env var name '${n}'."
    ) env;

  # The evaluated spec, normalized for rendering: files resolved to their paths
  # and any function-valued env/args/prefix applied to them, so a caller can
  # write `env.CONFIG = files: files."app.conf"`. Contributors and stub shapes
  # both see concrete values.
  #
  # Contributor namespaces are carried through untouched: the spec a contributor
  # receives is this one, so its own options sit next to the core fields.
  resolveSpec =
    cfg:
    let
      files = lib.mapAttrs (_: f: f.path) cfg.files;
      resolve = v: if lib.isFunction v then v files else v;
      resolved = cfg // {
        inherit files;
        args = map resolve cfg.args;
        env = lib.mapAttrs (_: resolve) cfg.env;
        prefix = map resolve cfg.prefix;
      };
    in
    # So a contributor naming whatever it builds does not re-derive the rule.
    resolved
    // {
      binName = binNameOf resolved;
    };

  # The name of the wrapped command: an explicit name, else the chosen
  # executable, else the package's main program. Only meaningful with a package,
  # so in text mode `name` is required instead.
  binNameOf =
    spec:
    if spec.name != null then
      spec.name
    else if spec.exe != null then
      spec.exe
    else
      baseNameOf (lib.getExe spec.package);

  # Whether a field carries anything: an empty list or attrset, an empty string,
  # or a null is the same as saying nothing.
  isSet =
    spec: field:
    let
      v = spec.${field} or null;
    in
    if builtins.isList v then
      v != [ ]
    else if builtins.isAttrs v then
      v != { }
    else if builtins.isString v then
      v != ""
    else
      v != null;

  # The executable to wrap inside a program, honoring `exe`. makeWrapper wants the
  # path, not the derivation.
  programPath =
    spec: program:
    if spec.exe != null then "${lib.getBin program}/bin/${spec.exe}" else lib.getExe program;
in
{
  inherit
    binNameOf
    commonModule
    coreOptions
    stubShapes
    envExportLines
    fileType
    filesOptions
    isSet
    programPath
    resolveSpec
    stubOptions
    ;

  checkAssertions =
    cfg:
    let
      failed = builtins.filter (a: !a.assertion) cfg.assertions;
    in
    if failed == [ ] then
      cfg
    else
      throw "substrate(wrappers): ${lib.concatMapStringsSep "; " (a: a.message) failed}";

  # Builder snippets shared by the stub shapes.
  fileLinks =
    files:
    lib.mapAttrsToList (n: p: ''
      mkdir -p "$(dirname "$out/${n}")"
      ln -s ${lib.escapeShellArg (toString p)} "$out/${n}"
    '') files;

  aliasLinks = binName: lib.map (a: ''ln -s ${lib.escapeShellArg binName} "$out/bin/${a}"'');

  # Core-owned passthru: the wrapped package, re-wrap with an overridden
  # package, the resolved files, plus whatever the caller set. `cfg` is the
  # resolved spec, so its files are already paths.
  finalize =
    {
      cfg,
      drv,
      rerun,
      wrapped,
    }:
    # Forcing the derivation forces the cross-field rules the pipeline checked on
    # the way here: `overrideAttrs` does not evaluate its input, so without this a
    # wrapper that breaks one would only fail at build time.
    (builtins.seq drv drv).overrideAttrs (
      _finalAttrs: previousAttrs: {
        passthru =
          (previousAttrs.passthru or { })
          // cfg.passthru
          // {
            inherit wrapped;
            override = pkgArgs: rerun { package = wrapped.override pkgArgs; };
          }
          // (lib.optionalAttrs (cfg.files != { }) { files = cfg.files; });
      }
    );
}
