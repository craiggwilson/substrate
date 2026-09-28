# The package builders, one per wrapper shape. The shapes differ only in what
# the output's bin/ directory holds:
#
#   wrap     the package tree, one executable replaced by a shell stub (and,
#            when the core has something to carry, by a stub plus the program)
#   binary   the same tree, with a compiled stub instead of a shell one
#
# Both go through symlinkJoin so a wrapper carries the same tree as its package
# whatever else is in the spec: a contributor contributing a chain fragment, a
# setup snippet, or a different program changes what the stub runs, not what the
# output contains.
{
  lib,
  pkgs,
  common,
  render,
}:
let
  inherit (common)
    aliasLinks
    binNameOf
    fileLinks
    programPath
    ;

  # The paths symlinkJoin links. It stringifies each one, so naming a package
  # links its default output and nothing more -- a package that keeps its man
  # pages in a separate `man` output (rclone, fzf) would lose them from a tree
  # meant to stand in for that package. What it declares in
  # meta.outputsToInstall is what it says should be installed, so that is what
  # the tree carries: a package holding outputs it declines to install
  # (ghostty's terminfo, vim and man) still links only its default output.
  # The wrapper stays a single output whatever it links, which is why its own
  # outputsToInstall below says `out` instead of inheriting this list.
  treePaths =
    drv:
    [ drv ]
    ++ map (output: drv.${output}) (
      lib.filter (output: output != "out" && drv ? ${output}) (drv.meta.outputsToInstall or [ "out" ])
    );

  # What the wrapper claims to be, as opposed to what treePaths linked into it.
  # The package's meta comes along because most of it (license, description,
  # platforms) is the wrapper's too, and its outputsToInstall cannot: that is a
  # claim about the package's own outputs, and inheriting it has buildenv ask
  # the wrapper for a `man` output a single-output derivation does not have. The
  # declared outputs are inside this one `out`, so the claim is `[ "out" ]`.
  metaFor =
    spec:
    (spec.package.meta or { })
    // {
      mainProgram = spec.binName;
      outputsToInstall = [ "out" ];
    };

  # The executable being replaced, and whether the wrapper's name differs from
  # it. `name` renames: the original is removed rather than left beside the
  # wrapper, so `aliases` is the only way to have both names. Other executables
  # in bin/ are left alone — a wrapper is one command, but the tree it came from
  # is not ours to prune.
  # The executable being replaced: what `exe` picked, else the one `name` resolved
  # to when it was not given -- the package's own.
  originalName = spec: if spec.exe != null then spec.exe else baseNameOf (lib.getExe spec.package);

  rename =
    spec:
    lib.optionalString (spec.name != null && spec.name != originalName spec) ''
      rm -f "$out/bin/${originalName spec}"
    '';

  treeLinks =
    spec: builtins.concatStringsSep "\n" (fileLinks spec.files ++ aliasLinks spec.binName spec.aliases);

  ## package wrapper

  # A compiled stub carries everything through makeWrapper-style flags, so it has
  # no room for an exec chain. The pipeline rejects that pairing before here (a
  # compiled stub plus a chain is an error, not a silently dropped prefix), which
  # is what lets this shape write the stub in one step.
  buildBinary =
    spec:
    let
      binName = spec.binName;
      flags = render.binaryFlags spec;
    in
    pkgs.symlinkJoin {
      name = "${lib.getName spec.program}-wrapped-binary";
      paths = treePaths spec.program;
      meta = metaFor spec;
      nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
      postBuild = ''
        ${rename spec}
        makeBinaryWrapper ${programPath spec spec.program} "$out/bin/${binName}" ${
          lib.optionalString (flags != "") "''${flags}''"
        } --inherit-argv0
        ${render.desktopPatch spec.program}
        ${treeLinks spec}
      '';
    };

  # The shell stub: the package tree with one executable replaced by a script
  # that sets the environment above the chain, plus a hidden makeWrapper'd program
  # when the core has args or a pre-hook to carry. See render.nix for why the
  # split exists.
  buildWrap =
    spec:
    let
      binName = spec.binName;
      # Spec's own runtimeInputs first: they are what the program needs, and a
      # contributor's PATH entries are additions for its own chain.
      pathEnv = lib.makeBinPath (spec.runtimeInputs ++ spec.extraRuntimeInputs);
      # `@out@` stands in for the final output path, which is not known until
      # the build runs; substitute puts it in below. The stub cannot name $out
      # directly because it is written before the output exists.
      outer = pkgs.writeShellScript "${binName}-outer" (render.toOuter spec pathEnv);
      needsCore = render.needsCore spec;
    in
    pkgs.symlinkJoin {
      name = "${lib.getName spec.program}-wrapped";
      paths = treePaths spec.program;
      meta = metaFor spec;
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        ${lib.optionalString needsCore ''
          makeWrapper ${programPath spec spec.program} "$out/bin/.${binName}-core" ${render.coreFlags spec} --inherit-argv0
        ''}
        # Written beside the target and moved over it: writing straight to
        # $out/bin/<name> would follow the tree's symlink into the store.
        # --replace-fail only when the placeholder is expected, since a stub
        # with no core names the program directly and has nothing to replace.
        substitute ${outer} "$out/bin/.${binName}-outer" ${lib.optionalString needsCore ''--replace-fail "@out@" "$out"''}
        chmod +x "$out/bin/.${binName}-outer"
        ${rename spec}
        mv -f "$out/bin/.${binName}-outer" "$out/bin/${binName}"
        ${render.desktopPatch spec.program}
        ${treeLinks spec}
      '';
    };
in
{
  inherit
    buildBinary
    buildWrap
    ;
}
