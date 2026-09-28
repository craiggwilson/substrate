# Shared machinery for the wrap pipeline: the common option prelude every
# backend is evaluated against, cross-field assertions, the file option type,
# snippet helpers, and passthru finalization. Backend-specific options and
# derivations live in builtins.nix; contributed backends declare only
# { options, build } and get all of this for free.
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

  # Options every backend receives: package (honored by every build per the
  # backend contract; text-mode wrappers leave it null), passthru, and the
  # internal cross-field assertion sink.
  commonModule = {
    options.package = lib.mkOption {
      type = with lib.types; nullOr package;
      default = null;
      description = "The package to wrap. Required by every backend except text-mode wrap.withScript.";
    };

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
      description = "Cross-field rules contributed by backend interfaces.";
    };
  };
in
{
  inherit commonModule fileType;

  checkAssertions =
    cfg:
    let
      failed = builtins.filter (a: !a.assertion) cfg.assertions;
    in
    if failed == [ ] then
      cfg
    else
      throw "substrate(wrappers): ${lib.concatMapStringsSep "; " (a: a.message) failed}";

  # Values in env/args/prefix may be functions; those are applied to the
  # files attrset (name -> resolved path) so a single call can reference its
  # own generated files. Adds `files` (resolved name -> path) to the result.
  resolveFns =
    cfg:
    let
      files = if cfg ? files then lib.mapAttrs (_: f: f.path) cfg.files else { };
      resolve = v: if lib.isFunction v then v files else v;
    in
    cfg
    // {
      inherit files;
      env = lib.mapAttrs (_: resolve) (cfg.env or { });
      args = map resolve (cfg.args or [ ]);
      prefix = map resolve (cfg.prefix or [ ]);
    };

  # Builder snippets shared by the built-in backends.
  fileLinks =
    files:
    lib.mapAttrsToList (n: p: ''
      mkdir -p "$(dirname "$out/${n}")"
      ln -s ${lib.escapeShellArg (toString p)} "$out/${n}"
    '') files;

  aliasLinks = binName: lib.map (a: ''ln -s ${lib.escapeShellArg binName} "$out/bin/${a}"'');

  # Core-owned passthru: the original package, re-wrap-with-overridden-package,
  # resolved files, plus whatever the caller set.
  finalize =
    {
      cfg,
      drv,
      rerun,
    }:
    drv.overrideAttrs (
      _finalAttrs: previousAttrs: {
        passthru =
          (previousAttrs.passthru or { })
          // cfg.passthru
          // {
            wrapped = cfg.package;
            override = pkgArgs: rerun { package = cfg.package.override pkgArgs; };
          }
          // lib.optionalAttrs (cfg ? files) {
            files = lib.mapAttrs (_: f: f.path) cfg.files;
          };
      }
    );
}
