# Pure SecretSpec manifest generation: the secretspec option namespace ->
# secretspec.toml text. Declarations only; secret values never appear here and
# are resolved by the secretspec CLI at runtime. Also owns where each class's
# manifest lives at runtime (`paths`).
#
# `manifestFile` is the single implementation of "the manifest for this
# configuration": both class modules and the wrappers extension's secrets
# contributor call it, so a wrapper reads byte-for-byte the file the
# configuration wrote — same name, same content, same store path.
{ lib }:
let
  # TOML basic-string escaping for the characters that can realistically occur
  # in configuration text. replaceStrings does a single simultaneous pass, so
  # backslashes are never double-escaped.
  escapeString =
    s:
    builtins.replaceStrings
      [
        "\\"
        "\""
        "\n"
        "\r"
        "\t"
      ]
      [
        "\\\\"
        "\\\""
        "\\n"
        "\\r"
        "\\t"
      ]
      s;

  renderValue =
    v:
    if lib.isBool v then
      if v then "true" else "false"
    else if lib.isInt v then
      toString v
    else if lib.isList v then
      "[ ${lib.concatMapStringsSep ", " renderValue v} ]"
    else if lib.isAttrs v then
      "{ ${lib.concatStringsSep ", " (lib.mapAttrsToList (k: val: "${k} = ${renderValue val}") v)} }"
    else
      ''"${escapeString (toString v)}"'';

  namePattern = "^[A-Za-z_][A-Za-z0-9_]*$";

  checkName =
    kind: name:
    if builtins.match namePattern name != null then
      name
    else
      throw "substrate(secrets): invalid ${kind} name '${name}'. Names must match ${namePattern} (secret names become environment variable names).";

  # Drop null fields; secretspec treats absent as "not set".
  cleanAttrs = lib.filterAttrs (_: v: v != null);

  # SecretSpec's native address with absent coordinates dropped: secretspec
  # treats a missing coordinate as "not set", and renderValue would stringify a
  # null as "".
  refAttrs =
    r:
    cleanAttrs {
      field = r.field or null;
      item = r.item or "";
      section = r.section or null;
      vault = r.vault or null;
      version = r.version or null;
    };

  refDecl =
    name: r:
    if (r.item or "") == "" then
      throw "substrate(secrets): entry '${name}' has a ref without an item (ref = { item = \"...\"; field = \"...\"; })."
    else
      refAttrs r;

  # A provider credential is either a bare provider spec, read at that
  # provider's convention address ({project}/_provider/<credential name>), or
  # a table pinning an explicit address — a flat token file, or an item field
  # in another secret store.
  credentialDecl =
    alias: c:
    if lib.isString c then
      c
    else
      cleanAttrs {
        provider = c.provider or null;
        ref =
          if (c.ref or null) == null then
            null
          else if (c.ref.item or "") == "" then
            throw "substrate(secrets): provider '${alias}' has a credential address without an item (credentials.<name> = { provider = \"...\"; ref = { item = \"...\"; }; })."
          else
            refAttrs c.ref;
      };

  # Field defaults live in the option module; reads here are total so raw
  # attrsets (validation probes, partial declarations) never crash the
  # renderer. secretspec rejects the whole manifest when a secret has no
  # description (Secret::validate_description), so require one here rather than
  # let it surface as a load-time failure against a generated file.
  entryDecl =
    name: e:
    if (e.description or "") == "" then
      throw "substrate(secrets): entry '${name}' has no description; secretspec requires a non-empty description for every secret."
    else
      cleanAttrs {
        description = e.description or "";
        required = if e.required or true then null else false;
        default = e.default or null;
        prompt = if e.prompt or false then true else null;
        as_path = if e.asPath or false then true else null;
        composed = e.composed or null;
        providers = if (e.providers or [ ]) == [ ] then null else e.providers;
        ref = if e.ref or null == null then null else refDecl name e.ref;
      };

  providerDecl =
    alias: p:
    if (p.uri or "") == "" then
      throw "substrate(secrets): provider '${alias}' has no uri."
    else if (p.credentials or { }) == { } then
      p.uri
    else
      {
        inherit (p) uri;
        credentials = lib.mapAttrs (_: credentialDecl alias) (p.credentials or { });
      };

  validateScopes =
    entries: scopes:
    let
      unknown = lib.concatMap (scope: lib.filter (s: !(entries ? ${s})) scope.secrets) (
        builtins.attrValues scopes
      );
    in
    if unknown == [ ] then
      scopes
    else
      throw "substrate(secrets): scopes reference unknown secrets: ${lib.concatStringsSep ", " unknown}";

  # Render a TOML table section with a leading blank line; nothing is emitted
  # for empty bodies.
  section = header: body: lib.optionalString (body != "") "\n${header}\n${body}\n";
  nixosEtcKey = "secretspec.toml";
  homeManagerRel = "secretspec/secretspec.toml";

  # An entry resolves to either a value (fetched by the wrapper, exposed to
  # as_path temp files by the CLI) or a materialized runtime file (file
  # policy); as_path changes what `secretspec get` returns, so the two
  # materialization modes conflict. A composed entry renders its value from
  # other entries and may not carry its own source (ref/providers/default).
  # Returns null or throws.
  checkConflict =
    entries:
    lib.foldlAttrs (
      acc: name: e:
      let
        composed = e.composed or null;
        filePolicy = (e.file or null) != null;
      in
      if acc != null then
        acc
      else if filePolicy && (e.asPath or false) then
        throw "substrate(secrets): entry '${name}' cannot set both asPath and file materialization; keep one."
      else if composed != null && (e.ref or null != null) then
        throw "substrate(secrets): composed entry '${name}' cannot set ref; references belong in the composed value."
      else if composed != null && (e.providers or [ ]) != [ ] then
        throw "substrate(secrets): composed entry '${name}' cannot set providers; add them to the referenced entries."
      else if composed != null && (e.default or null) != null then
        throw "substrate(secrets): composed entry '${name}' cannot set default."
      else
        null
    ) null entries;
  render =
    {
      project,
      entries ? { },
      providers ? { },
      scopes ? { },
      defaultProviders ? [ ],
    }:
    let
      # builtins.seq forces name validation; the decl functions never use the
      # name otherwise, so it would stay an unforced thunk.
      checkedEntries = lib.mapAttrs (n: e: builtins.seq (checkName "secret" n) (entryDecl n e)) entries;
      # validates entry-policy conflicts (asPath/file/composed) at render time
      # for every consumer, not just the materializers
      checkedPolicies = builtins.seq (checkConflict entries) true;
      checkedProviders = lib.mapAttrs (
        n: p: builtins.seq (checkName "provider" n) (providerDecl n p)
      ) providers;
      checkedScopes = validateScopes entries (
        builtins.listToAttrs (
          builtins.map (scope: {
            name = checkName "scope" scope;
            value = scopes.${scope};
          }) (builtins.attrNames scopes)
        )
      );

      providerLines = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (alias: p: "${alias} = ${renderValue p}") checkedProviders
      );
      profileBody = builtins.seq checkedPolicies (
        lib.concatStringsSep "\n" (
          lib.filter (s: s != "") [
            (lib.optionalString (
              defaultProviders != [ ]
            ) "defaults = { providers = ${renderValue defaultProviders} }")
            (lib.concatStringsSep "\n" (
              lib.mapAttrsToList (name: decl: "${name} = ${renderValue decl}") checkedEntries
            ))
          ]
        )
      );
      scopeSections = lib.concatStrings (
        lib.mapAttrsToList (
          scope: s: section "[scopes.${scope}]" "secrets = ${renderValue s.secrets}"
        ) checkedScopes
      );
    in
    ''
      [project]
      revision = "1.0"
      name = "${escapeString project}"
    ''
    + section "[providers]" providerLines
    + section "[profiles.default]" profileBody
    + scopeSections;

  # The manifest for a `secretspec` configuration: a store file by default, so
  # there is nothing to place on disk and nothing to activate in order. The render
  # is a pure function of the option subtree, which is what lets a wrapper anywhere
  # in the configuration reproduce the same store path rather than being told where
  # it is.
  manifestFile =
    pkgs: cfg:
    pkgs.writeText nixosEtcKey (render {
      inherit (cfg) project;
      inherit (cfg)
        entries
        providers
        scopes
        defaultProviders
        ;
    });
in
{
  # The manifest for a `secretspec` configuration. Public because a wrapper in
  # the same configuration renders it too, and lands on the same store path;
  # `render` is public with it, since that is the text it writes.
  inherit manifestFile render;

  # Where each class's generated manifest lives at runtime. The NixOS path is
  # fixed (systemd wrappers pass it via --file); the Home Manager path is
  # relative to config.xdg.configHome and exported as $SECRETSPEC_FILE.
  inherit checkConflict;

  paths = {
    inherit nixosEtcKey;
    nixosManifest = "/etc/${nixosEtcKey}";
    homeManagerManifest = homeManagerRel;
    # Shell-expandable form of the Home Manager manifest location, for
    # runtime helpers that are built before the user's configHome is known.
    # Split concatenation: a double-quoted string cannot hold a literal
    # `${...}` (the sequence is parsed as interpolation).
    homeManagerUserManifest = "$" + "{XDG_CONFIG_HOME:-$HOME/.config}/${homeManagerRel}";
  };

  # Shared materialization body for both class modules: fetch each
  # materialized entry's value into a temp file, then install it into place
  # with owner/group/mode. Values only ever live in runtime files; the store
  # only sees the manifest's declarations. manifestPath is interpolated into
  # the `--file` argument verbatim, so callers pass it shell-escaped.
  materializerText =
    {
      secretspec,
      coreutils,
      manifestPath,
    }:
    entries:
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: e:
        let
          f = e.file;
        in
        ''
          echo "Materializing secret ${name} to ${f.path}" >&2
          valueFile="$(mktemp)"
          ${secretspec}/bin/secretspec get ${name} --file ${manifestPath} > "$valueFile"
          ${coreutils}/bin/install -D \
            -m ${lib.escapeShellArg f.mode} \
            -o ${lib.escapeShellArg f.fileOwner} \
            -g ${lib.escapeShellArg f.fileGroup} \
            "$valueFile" ${lib.escapeShellArg f.path}
        ''
      ) (lib.filterAttrs (_: e: e.file != null) entries)
    );

}
