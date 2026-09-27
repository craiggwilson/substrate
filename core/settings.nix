{ lib, ... }:
{
  options.substrate.settings = {
    systems = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "List of systems to build for.";
      default = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
    };

    modulesFinder = lib.mkOption {
      type = lib.types.enum [ "all" ];
      description = "The name of the modules finder to use.";
      default = "all";
    };

    nixpkgsConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      description = ''
        Base nixpkgs configuration baked into every package set substrate
        creates (host and standalone user package sets). Per-entity overrides
        go in substrate.hosts.<name>.nixpkgsConfig or
        substrate.users.<name>.nixpkgsConfig. Package sets must be configured
        at instance creation, so setting nixpkgs.config inside a host/user
        module conflicts with this and is rejected by nixpkgs itself.
      '';
      default = { };
    };

    supportedClasses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "The supported module classes. Extensions add their classes here.";
      default = [ ];
    };

    extraArgsGenerators = lib.mkOption {
      type = lib.types.listOf (lib.types.functionTo lib.types.attrs);
      description = ''
        Functions to compute extra specialArgs (module arguments) for output
        configurations. This is the shared extension point for helpers that
        modules need, whether static or dependent on build context.
        Receives: { hostcfg, usercfg, inputs, pkgs }
        hostcfg is null for standalone user configurations and usercfg is null
        for host configurations; pkgs matches the build target
        (host system pkgs for host builds, user system pkgs for user builds).
        Returns: attrset merged into specialArgs
      '';
      default = [ ];
    };

    perHostContributors = lib.mkOption {
      type = lib.types.listOf (lib.types.functionTo (lib.types.listOf lib.types.unspecified));
      description = ''
        Contributors that add modules to each host configuration.
        Each function receives { inputs, substrate, hostname, hostcfg, userConfigs, pkgs }
        and returns a list of modules appended to the host's module list.
        Contributors should accept extra context fields (end patterns with ...).
        Extensions push contributions here; host builders consume them,
        so neither side needs to know about the other.
      '';
      default = [ ];
    };

    perUserContributors = lib.mkOption {
      type = lib.types.listOf (lib.types.functionTo (lib.types.listOf lib.types.unspecified));
      description = ''
        Contributors that add modules to each user configuration.
        Each function receives { inputs, substrate, userName, usercfg, pkgs }
        and returns a list of modules appended to the user's module list.
        Contributors should accept extra context fields (end patterns with ...).
        Extensions push contributions here; user builders consume them,
        so neither side needs to know about the other.
      '';
      default = [ ];
    };
  };
}
