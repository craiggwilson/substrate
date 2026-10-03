# Pure SecretSpec manifest generation: the secretspec option namespace ->
# secretspec.toml text. Declarations only; secret values never appear here and
# are resolved by the secretspec CLI at runtime.
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
    if v == true then
      "true"
    else if v == false then
      "false"
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

  refDecl =
    name: r:
    if (r.item or "") == "" then
      throw "substrate(secrets): entry '${name}' has a ref without an item (ref = { item = \"...\"; field = \"...\"; })."
    else
      cleanAttrs {
        vault = r.vault or null;
        item = r.item;
        field = r.field or null;
        section = r.section or null;
      };

  # Field defaults live in the option module; reads here are total so raw
  # attrsets (validation probes, partial declarations) never crash the
  # renderer.
  entryDecl =
    name: e:
    cleanAttrs {
      description = if (e.description or "") == "" then null else e.description;
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
        uri = p.uri;
        credentials = p.credentials;
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
      else if composed != null && (e.asPath or false) then
        throw "substrate(secrets): composed entry '${name}' cannot set asPath."
      else
        null
    ) null entries;
in
{
  # Where each class's generated manifest lives at runtime. The NixOS path is
  # fixed (systemd wrappers pass it via --file); the Home Manager path is
  # relative to config.xdg.configHome and exported as $SECRETSPEC_FILE.
  checkConflict = checkConflict;

  paths = {
    nixosEtcKey = nixosEtcKey;
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
  # the `--file` argument verbatim, so callers pass quotes around
  # shell-expandable paths.
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
      name = "${escapeString project}"
    ''
    + section "[providers]" providerLines
    + section "[profiles.default]" profileBody
    + scopeSections;
}
