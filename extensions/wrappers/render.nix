# The one wrapper shape, rendered from the core vocabulary plus what the
# contributors assembled: `chain`, `setup`, `extraRuntimeInputs`.
#
# The wrapper is the package tree with one executable replaced. Two files sit
# where that executable was:
#
#   $out/bin/<name>          the stub: environment, PATH, setup, then the chain
#   $out/bin/.<name>-core    the program itself, makeWrapper'd
#
# The split is what lets args and the pre-hook run at the innermost point of
# the chain: an entry like "$GREETING" is interpolated by the core's shell, so
# it expands *after* everything the chain did — a secretspec invocation
# injecting a token, say. With no chain to wait for, and nothing for the core to
# carry, the second file is skipped and the stub execs the program directly.
#
# toOuter is the pure text builder, exported so the rendered script can be
# asserted directly rather than by reading a built derivation.
{
  lib,
  pkgs,
  common,
}:
let
  inherit (common)
    aliasLinks
    binNameOf
    envExportLines
    fileLinks
    isSet
    programPath
    ;

  # makeWrapper's flags for the innermost point of the chain. Only args and the
  # pre-hook: both must run against the environment the chain produced. The
  # environment itself is applied above the chain by the stub, which is what
  # lets `--add-flags "--greeting $GREETING"` see a token secretspec just
  # resolved.
  coreFlagsList =
    spec:
    (lib.optionals (spec.args != [ ]) [
      "--add-flags"
      # Joined, not per-element escaped: makeWrapper interpolates --add-flags
      # verbatim into the bash-interpreted invocation, so pre-escaping here would
      # make "$VAR" a literal string. Callers that want literal values pre-escape
      # with lib.escapeShellArgs themselves.
      (lib.concatStringsSep " " spec.args)
    ])
    ++ lib.optionals (spec.preHook != "") [
      "--run"
      spec.preHook
    ];

  coreFlags = spec: lib.concatStringsSep " " (builtins.map lib.escapeShellArg (coreFlagsList spec));

  # A compiled stub has no chain to defer to, so the whole vocabulary arrives as
  # flags: the environment, PATH, then what the shell stub would have carried
  # innermost. Same escaping either way, so it is built from the same pieces.
  binaryFlags =
    spec:
    lib.concatStringsSep " " (
      builtins.map lib.escapeShellArg (
        lib.concatLists (
          lib.mapAttrsToList (n: v: [
            "--set"
            n
            (toString v)
          ]) spec.env
        )
        ++ lib.optionals (spec.runtimeInputs != [ ]) [
          "--prefix"
          "PATH"
          ":"
          (lib.makeBinPath spec.runtimeInputs)
        ]
        ++ coreFlagsList spec
      )
    );

  # Whether the core has anything to carry. If not, the stub can exec the
  # program itself and there is no second file in the output.
  needsCore = spec: spec.args != [ ] || spec.preHook != "";

  # Everything the wrapper puts in the environment before the chain runs: the
  # spec's own exports, then the spec's runtimeInputs ahead of any contributor's
  # (a contributor adds tools the wrapped program needs, not a competing PATH).
  preamble =
    spec: pathEnv:
    lib.concatStringsSep "\n" (
      lib.filter (s: s != "") (
        envExportLines spec.env
        ++ lib.optionals (pathEnv != "") [ ''PATH="${pathEnv}:$PATH"'' ]
        ++ lib.optionals (spec.setup != "") [ spec.setup ]
      )
    );

  # The stub. `@out@` is replaced with the final output path in the builder;
  # "$0"/"$@" are runtime literals. A postHook disables exec so the program's
  # exit code can be handed on.
  toOuter =
    spec: pathEnv:
    let
      binName = spec.binName;
      # The program the chain runs: the core when one exists, so the core's flags
      # land on it, and the program itself when nothing needs carrying.
      target = if needsCore spec then "@out@/bin/.${binName}-core" else programPath spec spec.program;
      launch = lib.concatStringsSep " " (spec.chain ++ [ target ]);
      execLine = ''exec -a "$0" ${launch} "$@"'';
    in
    if needsCore spec then
      lib.concatStringsSep "\n" (
        lib.filter (s: s != "") [
          (preamble spec pathEnv)
          (
            if spec.postHook != "" then
              ''
                ( ${execLine} )
                code=$?
                ${spec.postHook}
                exit $code
              ''
            else
              execLine
          )
        ]
      )
    else
      lib.concatStringsSep "\n" (
        lib.filter (s: s != "") [
          (preamble spec pathEnv)
          (
            if spec.postHook != "" then
              ''
                ( ${execLine} )
                code=$?
                ${spec.postHook}
                exit $code
              ''
            else
              execLine
          )
        ]
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

in
{
  inherit
    binaryFlags
    coreFlags
    desktopPatch
    needsCore
    toOuter
    ;
}
