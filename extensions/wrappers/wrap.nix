# The wrap pipeline: evaluate one spec against the core vocabulary plus the
# options of every registered contributor, let the contributors add what they
# contribute, and render exactly one wrapper.
#
# There is one wrapper per call and no folding. A spec is the core vocabulary
# (package, env, args, …) flat at the top level, plus at most one key per
# contributor it names — `secrets.scope`, `bubblewrap.permissions`. Contributors
# are ordered by their declared `priority` (lower = further from the program) and
# may only add: exec-chain fragments, PATH entries, a setup snippet, a different
# program to wrap, and the names of the environment variables they introduce.
# Nothing here renders a contributor's options, and nothing a contributor does
# can drop a core field — a shape that cannot honor one declares it in
# `incompatible`, which is then an error rather than a silent omission.
#
# There is one mode: a wrapper wraps a package. Writing a script is nixpkgs' job
# (`pkgs.writeShellApplication`, `writeScriptBin`), and wrapping the result is
# what this is for.
#
# Usage (as the `wrap` module argument, see class-module.nix):
#
#   wrap.package { package; env; args; ... }     # a wrapper over a package
#   wrap.package { package; secrets.scope; ... }  # a contributor joins in
#   wrap.package { package = wrap.package { … }; … }  # stacking is nesting calls
{
  lib,
  pkgs,
  contributors ? { },
  # The build context this wrap argument was built for. Every contributor hook
  # receives it, so one can adapt to it: the host/user split decides whether a
  # host build needs an XDG fallback for a unit with no HOME.
  hostcfg ? null,
  usercfg ? null,
  inputs ? { },
  # The configuration this wrap argument belongs to: the NixOS or Home Manager
  # config whose modules can call wrap. Published by the class module
  # (class-module.nix) because that is the only place a module argument can
  # close over the configuration it belongs to. An extraArgsGenerator runs in the
  # builder, outside the configuration being built, so a generator has no config
  # to name; nixpkgs does not apply function-valued args either, so a closure
  # would arrive unapplied. A contributor hook that reads config ties its
  # wrapper to that configuration, which is the point: it is how a wrapper reads
  # the options declared beside it rather than a copy of them.
  config ? null,
}:
let
  common = import ./common.nix { inherit lib pkgs; };
  # What a contributor gets: the shared vocabulary, plus the build context.
  wrapLib = common;
  render = import ./render.nix {
    inherit
      lib
      pkgs
      common
      ;
  };
  builders = import ./builders.nix {
    inherit
      lib
      pkgs
      common
      render
      ;
  };

  # A contributor's `options` is an attrset of mkOption declarations, a full
  # module body (imports/options/config), or a module function -- all three shapes
  # cost the same here, so they are accepted rather than one being canonical.
  toModule =
    opts:
    if lib.isFunction opts then
      opts
    else if
      builtins.any (k: builtins.hasAttr k opts) [
        "options"
        "config"
        "imports"
      ]
    then
      opts
    else
      { options = opts; };

  # The build context every contributor hook receives. A contributor's own
  # `context` hook adds whatever it needs (jail-nix's callable, say) without any
  # other extension having to know about it.
  baseCtx = {
    inherit
      config
      inputs
      lib
      pkgs
      hostcfg
      usercfg
      wrapLib
      ;
  };

  contributorCtx =
    name:
    let
      c = contributors.${name};
    in
    if c ? context then baseCtx // c.context baseCtx else baseCtx;

  # One declaration per registered contributor, so a spec naming a contributor
  # whose extension is not loaded is an "option does not exist" error rather
  # than a silently ignored key.
  contributorOptions = name: {
    options.${name} = lib.mkOption {
      type = lib.types.submodule (toModule (contributors.${name}.options or { }));
      default = { };
      description = "Options for the `${name}` wrapper contributor.";
    };
  };

  # Contributor rules the option types cannot express. Returns the problems
  # found; the caller throws them, so the message names the actual cause.
  contributorProblems =
    {
      chain,
      chained,
      compiled,
      forwarded,
      ordered,
      resolved,
      setup,
    }:
    let
      ties = builtins.filter (g: builtins.length g > 1) (
        lib.attrValues (lib.groupBy (v: toString v.priority) ordered)
      );

      # A core field that a selected contributor declares it cannot honor.
      clashes = builtins.filter (v: lib.any (f: common.isSet resolved f) (v.incompatible or [ ])) ordered;

      # Forcing this is the point: a contributor that advertises a name a shell
      # cannot assign would otherwise only fail at run time, inside whatever is
      # supposed to forward it.
      badNames = builtins.filter (n: !(builtins.match "^[A-Za-z_][A-Za-z0-9_]*$" n != null)) forwarded;
    in
    lib.optionals (ties != [ ]) [
      "contributor(s) ${
        lib.concatMapStringsSep " and " (g: lib.concatStringsSep " & " (map (v: v.name) g)) ties
      } share a priority, so their order in the exec chain would be arbitrary. Give one a different priority."
    ]
    ++ lib.optionals (clashes != [ ]) [
      "contributor(s) ${
        lib.concatMapStringsSep ", " (
          v: "${v.name} (${lib.concatStringsSep ", " (v.incompatible or [ ])})"
        ) clashes
      } cannot honor the fields you set. Remove them, or nest the wrappers instead: wrap { package = wrap { … }; … }."
    ]
    ++ lib.optionals (badNames != [ ]) [
      "contributor(s) advertised environment variable(s) ${
        lib.concatStringsSep ", " (map (n: "'${n}'") badNames)
      }, which a shell cannot assign."
    ]
    ++ lib.optionals (compiled && chained) [
      "stub = \"makeBinaryWrapper\" cannot carry an exec chain, and this one has ${
        if chain != [ ] then
          "chain fragments"
        else if setup != "" then
          "a setup snippet"
        else
          "a different program"
      }. Use stub = \"makeWrapper\", which is what a chain needs."
    ];

  packageSpec =
    spec:
    let
      # A contributor participates when its key appears in the spec.
      selected = builtins.filter (n: builtins.hasAttr n spec) (builtins.attrNames contributors);

      cfg =
        common.checkAssertions
          (lib.evalModules {
            class = "wrap";
            modules = [
              common.coreOptions
            ]
            ++ map contributorOptions (builtins.attrNames contributors)
            ++ [
              spec
            ];
            specialArgs = {
              inherit
                pkgs
                lib
                wrapLib
                ;
            };
          }).config;

      resolved = common.resolveSpec cfg;

      # What each contributor advertises: the environment variables its prefix
      # will have introduced by the time the program runs. A contributor whose
      # shape scrubs the environment (a jail) needs these to forward them.
      envNamesOf =
        name:
        let
          c = contributors.${name};
        in
        if c ? envNames then c.envNames (contributorCtx name) resolved else [ ];

      forwarded = lib.unique (
        builtins.attrNames resolved.env ++ lib.concatLists (map envNamesOf selected)
      );

      view =
        name:
        let
          c = contributors.${name};
          ctx = contributorCtx name // {
            inherit forwarded;
          };
        in
        {
          inherit name;
          inherit (c) priority;
          incompatible = c.incompatible or [ ];
          prefixes = if c ? prefix then c.prefix ctx resolved else [ ];
          runtimeInputs = if c ? runtimeInputs then c.runtimeInputs ctx resolved else [ ];
          setup = if c ? setup then c.setup ctx resolved else "";
          program = if c ? program then c.program ctx resolved else null;
        };

      # Ascending priority: lower sits further out, so its chain runs first.
      ordered = lib.sort (a: b: a.priority < b.priority) (map view selected);

      # Innermost contributor first: each `program` hook receives what a more
      # inner one produced, so a chain of them wraps outward in priority order.
      program = lib.foldl' (acc: v: if v.program == null then acc else v.program acc) resolved.package (
        lib.reverseList ordered
      );

      chain = lib.concatLists (map (v: v.prefixes) ordered) ++ resolved.prefix;
      setup = builtins.concatStringsSep "\n" (map (v: v.setup) ordered);
      extraRuntimeInputs = lib.concatLists (map (v: v.runtimeInputs) ordered);

      # Whether an exec chain has to be carried, which a compiled stub cannot
      # hold. PATH entries are not a chain: the stub carries those itself.
      chained = chain != [ ] || setup != "" || program != resolved.package;
      compiled = resolved.stub == "makeBinaryWrapper";

      rendered = resolved // {
        binName = common.binNameOf resolved;
        inherit
          chain
          extraRuntimeInputs
          forwarded
          program
          setup
          ;
      };

      problems = contributorProblems {
        inherit
          chain
          chained
          compiled
          forwarded
          ordered
          resolved
          setup
          ;
      };

      # `problems` is forced here: these are rules the option types cannot
      # express, and a wrapper that breaks one must not silently build.
      drv =
        if problems != [ ] then
          throw "substrate(wrappers): ${lib.concatStringsSep " " problems}"
        else if compiled then
          builders.buildBinary rendered
        else
          builders.buildWrap rendered;

      rerun = overrides: packageSpec (spec // overrides);
    in
    common.finalize {
      cfg = resolved;
      inherit drv rerun;
      wrapped = resolved.package;
    };
in
# Forcing the contributor registry: an entry that does not declare what the
# option type checks (its priority) is a broken extension, and should say so here
# rather than when someone first names it.
builtins.seq (builtins.deepSeq contributors true) {
  # The one call there is. A spec is the core vocabulary flat at the top level,
  # plus at most one key per contributor it names.
  package = packageSpec;

  # Option types shared with contributor authors.
  types = {
    file = common.fileType pkgs;
  };
}
