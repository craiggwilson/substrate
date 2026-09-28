# Pure SecretSpec manifest generation: substrate.secrets configuration ->
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
in
{
  # Where each class's generated manifest lives at runtime. The NixOS path is
  # fixed (systemd wrappers pass it via --file); the Home Manager path is
  # relative to config.xdg.configHome and exported as $SECRETSPEC_FILE.
  paths = {
    nixosEtcKey = nixosEtcKey;
    nixosManifest = "/etc/${nixosEtcKey}";
    homeManagerManifest = "secretspec/secretspec.toml";
  };

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
      profileBody = lib.concatStringsSep "\n" (
        lib.filter (s: s != "") [
          (lib.optionalString (
            defaultProviders != [ ]
          ) "defaults = { providers = ${renderValue defaultProviders} }")
          (lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: decl: "${name} = ${renderValue decl}") checkedEntries
          ))
        ]
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
