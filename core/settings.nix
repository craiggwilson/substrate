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

    supportedClasses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "The supported module classes. Extensions add their classes here.";
      default = [ ];
    };

    extraArgsGenerators = lib.mkOption {
      type = lib.types.listOf (lib.types.functionTo lib.types.attrs);
      description = ''
        Function to compute extra specialArgs for output configurations.
        hostcfg will be null for standalone user configurations and
        usercfg will be null for host configurations.
        Receives: { hostcfg, usercfg, pkgs, inputs }
        Returns: attrset merged into specialArgs
      '';
      default = [ ];
    };

    perHostContributors = lib.mkOption {
      type = lib.types.listOf (lib.types.functionTo (lib.types.listOf lib.types.unspecified));
      description = ''
        Contributors that add modules to each host configuration.
        Each function receives { inputs, substrate, hostname, hostcfg, userConfigs }
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
        Each function receives { inputs, substrate, userName, usercfg }
        and returns a list of modules appended to the user's module list.
        Contributors should accept extra context fields (end patterns with ...).
        Extensions push contributions here; user builders consume them,
        so neither side needs to know about the other.
      '';
      default = [ ];
    };
  };
}
