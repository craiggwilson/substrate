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
        creates (host and host-scoped user package sets). Per-entity overrides
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
        usercfg is null for host configurations; hostcfg is null for no
        current builder (every user build is host-scoped or host-integrated)
        and generators should not assume it; pkgs matches the build target
        (host system pkgs for host builds, user system pkgs for user builds).
        Returns: attrset merged into specialArgs
      '';
      default = [ ];
    };

    contributors = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            class = lib.mkOption {
              type = lib.types.str;
              description = ''
                The module class this contribution is destined for (e.g., "nixos",
                "homeManager"). Only the builder that speaks this class consumes it,
                so a contribution is never loaded into a configuration whose target
                extension is absent. It is normal for a class to have no builder:
                an extension may target several builders, some of which a given
                configuration does not enable.
              '';
            };

            contribute = lib.mkOption {
              type = lib.types.functionTo (lib.types.listOf lib.types.unspecified);
              description = ''
                Function that receives the build context for the class and returns a
                list of modules to append to each matching configuration. The context
                shape follows the class: host classes receive
                { inputs, substrate, hostname, hostcfg, userConfigs, pkgs }, user
                classes receive { inputs, substrate, userName, usercfg, pkgs }.
                Contribute functions should accept extra context fields (end patterns
                with ...).
              '';
            };
          };
        }
      );
      default = [ ];
      description = ''
        Contributors that add modules to configurations. Each entry declares the
        class it targets; builders consume only the entries whose class they speak,
        via substrate.lib.contributionsFor. Extensions push contributions here so
        neither side needs to know about the other.
      '';
    };

    publishers = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            scope = lib.mkOption {
              type = lib.types.enum [
                "global"
                "perSystem"
              ];
              description = ''
                Whether the output is built once or once per system. Global
                outputs receive { inputs, coreInputs, substrate }; per-system
                outputs also receive { pkgs, system }.
              '';
            };

            output = lib.mkOption {
              type = lib.types.str;
              description = "The output name this key is published under.";
            };

            build = lib.mkOption {
              type = lib.types.functionTo lib.types.raw;
              description = ''
                Function producing the value the output carries. It reads the
                key off `substrate.publish`, so a publisher never closes over
                config. Receives the same context an output builder does.
              '';
            };
          };
        }
      );
      default = { };
      description = ''
        Named things this configuration publishes. Each entry turns one key of
        `substrate.publish` into one output; core walks the registry and creates
        the output builders, so an extension publishes by declaring its key and
        registering it here rather than by writing an output builder itself.

        A key reaches exactly one output. A value that belongs under two output
        names -- published packages, which also contribute an overlay -- keeps
        its extra output builder directly, the way any module can.
      '';
    };
  };
}
