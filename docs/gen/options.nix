# Generates the option reference chapter from the live module system.
#
# Documentation of an option path can drift away from the option it describes;
# walking the module system cannot. Every path, type and description below is
# read out of an actual `lib.evalModules` result, with all extensions loaded.
#
# Called from `flake.nix`, which writes the result to the book's
# `src/reference/options.md` before building. Never edit that file by hand.
{
  pkgs,
}:
let
  inherit (pkgs) lib;

  testLib = import ../../tests/lib.nix { inherit pkgs; };

  # Extensions that take their flake inputs as module arguments (the jail
  # extension does) need `inputs` bound. Stubs are enough: nothing in the
  # option tree forces an input, so a real flake would only slow this down.
  extensionNames = [
    "home-manager"
    "jail"
    "nixos"
    "overlays"
    "packages"
    "published-modules"
    "secrets"
    "shells"
    "tags"
    "types"
    "wrappers"
  ];
  # `overlays` and `packages` are already part of the core module set the
  # test library loads, and loading either twice is a duplicate declaration.
  loadedExtensions = lib.filter (n: n != "overlays" && n != "packages") extensionNames;

  stubInputs = {
    inherit (pkgs) nixpkgs;
    home-manager = { };
    home-manager-modules = { };
    jail-nix = { };
  };

  options =
    (lib.evalModules {
      modules =
        testLib.extendedCoreModules ++ map (name: import ../../extensions/${name}) loadedExtensions;
      specialArgs.inputs = stubInputs;
    }).options.substrate;

  # --- rendering helpers ---------------------------------------------------

  # Option descriptions are written as indented prose, so they carry newlines.
  # Collapse them; a markdown table cell cannot hold them.
  oneLine = text: lib.replaceStrings [ "\n" ] [ " " ] (lib.trim text);

  # A merged type's `description` is usually a string, but for a composite type
  # nixpkgs builds it from several parts and hands back a set. Coerce to a
  # string when we can and drop the type when we cannot — a missing type line
  # is better than a page that does not build.
  # Scalars only. A composite type describes itself with a *set* of strings,
  # and stringifying a set recurses into the type that produced it, so anything
  # that is not already a scalar or a list of scalars is reported as null
  # rather than coerced.
  # Descriptions are prose that names option paths, so they carry `<name>` and
  # `<user>`. Markdown reads those as HTML tags and warns; escaping keeps the
  # text as written.
  escapeAngle = text: lib.replaceStrings [ "<" ">" ] [ "&lt;" "&gt;" ] text;

  asString =
    value:
    if lib.isString value then
      lib.trim value
    else if lib.isBool value || lib.isInt value || lib.isFloat value || builtins.isNull value then
      toString value
    else if builtins.isList value && lib.all (item: lib.isString item) value then
      oneLine (lib.concatStringsSep " | " value)
    else
      null;

  triedString =
    expr:
    let
      attempt = builtins.tryEval expr;
    in
    if attempt.success then asString attempt.value else null;

  relPath =
    path:
    let
      full = toString path;
      root = "${toString ../../.}/";
    in
    if lib.hasPrefix root full then lib.removePrefix root full else full;

  # `x ? attr or default` only substitutes when the attribute is absent, and an
  # option may carry `declarations = null`, so test the value too.
  declaringFiles =
    option:
    let
      raw = if (option ? declarations) && option.declarations != null then option.declarations else [ ];
    in
    lib.unique (lib.map relPath (lib.filter (d: (toString d) != "<unknown-file>") raw));

  # The declared default, if it can be rendered without forcing anything that
  # might not terminate. An option with no useful default is left out rather
  # than printed as an evaluated store path.
  # The submodule an option introduces, when it introduces one. `getSubOptions`
  # needs an example list of argument names; the field names themselves are
  # never read, so any name will do.
  submodule =
    option:
    if !(option ? type) then
      { }
    else
      let
        attempt = builtins.tryEval (option.type.getSubOptions [ "example" ]);
      in
      if attempt.success && builtins.isAttrs attempt.value then attempt.value else { };

  isOption = node: (node ? type) && (node ? description);

  visibleNames = node: builtins.filter (name: !(lib.hasPrefix "_" name)) (builtins.attrNames node);

  # Flat list of { path, entry } in tree order. A node with no type is a plain
  # grouping attribute like `substrate.settings.publish`; a node with a type is
  # an option, and if it opens a submodule its fields follow it.
  walk =
    path: node:
    let
      children = visibleNames node;
      openable = submodule node;
      openNames = lib.filter (name: isOption openable.${name}) (visibleNames openable);
    in
    if !(node ? type) then
      lib.concatMap (name: walk "${path}.${name}" node.${name}) children
    else
      [ (node // { inherit path; }) ]
      ++ lib.concatMap (name: walk "${path}.${name}" openable.${name}) openNames;

  entries = walk "substrate" options;

  # Group under each direct child of `substrate`, which is what a reader is
  # navigating by: settings, hosts, users, modules, and so on.
  groupKey = entry: lib.head (lib.splitString "." (lib.removePrefix "substrate." entry.path));

  groupOrder = [
    "settings"
    "hosts"
    "users"
    "modules"
    "moduleFinders"
    "outputs"
    "packages"
    "types"
    "lib"
  ];
  present = lib.unique (lib.map groupKey entries);
  orderedGroups = lib.unique (groupOrder ++ present);

  renderEntry =
    entry:
    let
      # A type with no `descriptionClass` is a freeform type that reaches back
      # into itself — `substrate.modules` is one, and forcing its description
      # recurses forever. That is an abort, not a thrown error, so `tryEval`
      # cannot contain it and the only guard is to not ask. Such an option gets
      # no Type line; the chapters say what it is.
      hasClass = (entry ? type) && (entry.type ? descriptionClass) && entry.type.descriptionClass != null;

      typeText = if hasClass then triedString entry.type.description else null;
      files = declaringFiles entry;
      description =
        if entry ? description then
          let
            flat = asString entry.description;
          in
          if flat == null then null else escapeAngle (oneLine flat)
        else
          null;
      # A merged type hands back a set where a description is expected, so
      # `asString` above coerces what it can and reports null for the rest. A
      # reference missing a type line beats one that will not build.
      #
      # Declared defaults are deliberately absent. Rendering one means either
      # forcing configuration or serializing values nixpkgs will not put in
      # JSON, and the errors that raises escape `tryEval` because they happen
      # while serializing. Where a default matters, the option's own
      # description says so.
      body =
        lib.optional (typeText != null) "**Type** ${typeText}"
        ++
          lib.optional (lib.length files > 0)
            "**Declared in** ${lib.concatMapStringsSep ", " (f: "`${f}`") files}"
        ++ lib.optional (description != null) description;
    in
    ''
      ### `${entry.path}`

      ${lib.concatStringsSep "\n\n" body}

    '';

  groupSection = name: ''
    ## `substrate.${name}`

    ${lib.concatMapStrings renderEntry (lib.filter (entry: groupKey entry == name) entries)}
  '';

  page = ''
    <!-- Generated by docs/gen/options.nix. Do not edit: your changes will be
         overwritten. Change the option's description, or the generator. -->

    # Option Reference

    Every option substrate and its extensions declare, read out of the module
    system at build time.

    Options that open a submodule are followed by that submodule's fields, so
    `substrate.hosts` is followed by the options each host accepts and
    `substrate.settings.contributors` by the fields of each entry in the list.
    Paths are shown as declared: read `substrate.hosts.system` as the `system`
    option of a host, and `substrate.settings.contributors.class` as the
    `class` field of a contributor.

    The prose chapters are the better introduction to *why* an option exists;
    this page is the exhaustive index, and it cannot disagree with the code.

    ${lib.concatMapStrings groupSection orderedGroups}
  '';
  # The per-entry templates end in a blank line, so the last section leaves a
  # tail of them. `replaceStrings` matches literally and cannot collapse a run,
  # so peel one at a time.
  strip =
    text:
    let
      once = lib.removeSuffix "\n" text;
    in
    if once == text then text else strip once;

  trimmed = strip (page + "\n");
in
trimmed + "\n"
