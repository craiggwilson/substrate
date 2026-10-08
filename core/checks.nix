{
  lib,
  config,
  ...
}:
let
  inherit (config.substrate) settings;
  allModules = config.substrate.moduleFinders.all.find [ ];

  validateModuleClasses =
    let
      allClasses = [ "generic" ] ++ settings.supportedClasses;
      modulesWithUnsupportedClasses = lib.filter (
        m:
        let
          # Dynamically check all supported classes instead of hardcoding
          usedClasses = lib.filter (c: m ? ${c} && m.${c} != null) allClasses;
          unsupportedClasses = lib.filter (c: !(lib.elem c allClasses)) usedClasses;
        in
        unsupportedClasses != [ ]
      ) allModules;
    in
    {
      name = "module-classes";
      valid = modulesWithUnsupportedClasses == [ ];
      message =
        if modulesWithUnsupportedClasses == [ ] then
          "All modules use supported classes only"
        else
          "Found ${toString (lib.length modulesWithUnsupportedClasses)} modules using unsupported classes";
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
      validateModuleClasses
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
