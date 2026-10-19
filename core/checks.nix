{
  lib,
  config,
  ...
}:
let
  slib = config.substrate.lib;

  # The tree's freeform type cannot distinguish a module written for a class
  # nobody registered from a legitimate grouping node -- both are the same
  # shape -- so what is checkable is whether any finder can select the node at
  # all. A node no finder can select is dropped from every build with no error
  # of its own, which is why this warns rather than passing silently.
  #
  # The usual cause is a module written under a class whose extension is not
  # imported: `substrate.modules.programs.zfs.darwin = { ... }` with no darwin
  # extension reads as a plain nested node, and every class then finds nothing
  # under it.
  validateModuleReachability =
    let
      unreachable = slib.unreachableModulePaths config.substrate.modules;
    in
    {
      name = "module-reachability";
      valid = unreachable == [ ];
      warn = true;
      message =
        if unreachable == [ ] then
          "Every module in the tree is reachable by some supported class"
        else
          let
            details = lib.concatStringsSep "\n" (lib.map (p: "  - ${p}") unreachable);
            hint =
              " If a module was written under a class whose extension is not"
              + " imported, that class is not in supportedClasses and nothing"
              + " will build it.";
          in
          "Found ${toString (lib.length unreachable)} module paths that no supported class reaches:\n${details}${hint}";
    };

  validateHostUsers =
    let
      allUserNames = builtins.attrNames config.substrate.users;
      hostsWithInvalidUsers = lib.filterAttrs (
        _name: host:
        let
          invalidUsers = lib.filter (u: !(lib.elem u allUserNames)) (host.users or [ ]);
        in
        invalidUsers != [ ]
      ) config.substrate.hosts;
    in
    {
      name = "host-users";
      valid = hostsWithInvalidUsers == { };
      message =
        if hostsWithInvalidUsers == { } then
          "All hosts reference valid users"
        else
          let
            details = lib.concatStringsSep "\n" (
              lib.mapAttrsToList (
                name: host:
                let
                  invalidUsers = lib.filter (u: !(lib.elem u allUserNames)) (host.users or [ ]);
                in
                "  - Host '${name}': invalid users ${toString invalidUsers}"
              ) hostsWithInvalidUsers
            );
          in
          "Found hosts referencing invalid users:\n${details}";
    };
in
{
  options.substrate.settings.checks = lib.mkOption {
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Name of the check.";
          };
          valid = lib.mkOption {
            type = lib.types.bool;
            description = "Whether the check passed.";
          };
          warn = lib.mkOption {
            type = lib.types.bool;
            description = "If true, this check is a warning rather than an error.";
            default = false;
          };
          message = lib.mkOption {
            type = lib.types.str;
            description = "Message describing the check result.";
          };
        };
      }
    );
    description = "List of configuration validation checks. Extensions can add their own checks here.";
    default = [ ];
  };

  config.substrate = {
    settings.checks = [
      validateModuleReachability
      validateHostUsers
    ];

    # Render substrate.settings.checks as a per-system output builder so every
    # builder emits the same `checks.<system>.substrate-config` derivation.
    outputs.perSystem.checks = [
      {
        build =
          { pkgs, substrate, ... }:
          let
            allValidations = substrate.settings.checks;

            summary =
              let
                passed = lib.filter (v: v.valid) allValidations;
                warnings = lib.filter (v: !v.valid && (v.warn or false)) allValidations;
                failed = lib.filter (v: !v.valid && !(v.warn or false)) allValidations;
              in
              ''
                Substrate Configuration Validation
                ===================================
                Checks: ${toString (lib.length allValidations)}
                Passed: ${toString (lib.length passed)}
                Warnings: ${toString (lib.length warnings)}
                Failed: ${toString (lib.length failed)}

                ${lib.concatMapStringsSep "\n" (v: "${v.name}: ${v.message}") allValidations}
              '';

            evalWarnings =
              let
                warnings = lib.filter (v: !v.valid && (v.warn or false)) allValidations;
              in
              lib.concatMapStrings (v: lib.warn "substrate: ${v.name}: ${v.message}" "") warnings;

            evalErrors = lib.filter (v: !v.valid && !(v.warn or false)) allValidations;
            hasErrors = evalErrors != [ ];
            errorMessages = lib.concatMapStringsSep "\n" (v: "  - ${v.name}: ${v.message}") evalErrors;

            validated = builtins.seq evalWarnings (
              if hasErrors then
                throw ''
                  Substrate configuration validation failed!
                  ${errorMessages}
                ''
              else
                true
            );
          in
          {
            substrate-config =
              assert validated;
              pkgs.runCommand "substrate-config-validation" { } ''
                  echo "All substrate configuration checks passed!"
                  cat <<'EOF'
                ${summary}
                EOF
                  touch $out
              '';
          };
      }
    ];
  };
}
