# Conformance tests for the substrate builder contract.
#
# Builders differ only in where `lib` comes from and in the shape they return.
# Everything an extension can observe has to come out identical, so these tests
# hold one body and run it against every builder in `substrate.build`.
#
# This matters because a builder that drops or reshapes something degrades
# silently: extensions register output builders unconditionally and are lazy, so
# a builder that never calls one produces a smaller attrset rather than an
# error. The cases below cover the ways that stays invisible — skipping the
# perSystem walk, forgetting to bake settings.overlays into the package sets,
# failing to merge same-name output builders, and not passing inputs/coreInputs
# down as module arguments.
{
  pkgs ? import <nixpkgs> { },
  # flake.nix supplies the real flake inputs; the defaults provide
  # flake-shaped wrappers so the tests also work when evaluated directly.
  nixpkgsSrc ? {
    outPath = pkgs.path;
    inherit (pkgs) lib;
  },
  # Both are optional: without them the assertions that need those extensions,
  # and the flake-parts builder itself, are left out rather than failed.
  homeManagerSrc ? null,
  flakePartsSrc ? null,
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib runTests;

  substrate = import ../..;

  builders = {
    raw = substrate.build.raw;
    # substrate itself does not depend on flake-parts; consumers bring their
    # own, so these two builders are left out when it is not supplied.
  }
  // lib.optionalAttrs (flakePartsSrc != null) {
    flake = substrate.build.flake;
    with-flake-parts = substrate.build.with-flake-parts;
  };

  # flake-parts reads `self.outPath` for module locations, so the stub inputs
  # have to carry one rather than leaving the builder's default to fail.
  stubInputs = {
    nixpkgs = nixpkgsSrc;
  }
  // lib.optionalAttrs (homeManagerSrc != null) { home-manager = homeManagerSrc; }
  // lib.optionalAttrs (flakePartsSrc != null) { flake-parts = flakePartsSrc; }
  // {
    self = {
      outPath = builtins.dirOf ../..;
    };
  };

  system = "x86_64-linux";

  # What a consumer's inputs look like when they are deliberately not the set
  # roles resolve from: the transport entries a builder needs, different
  # content. `stubInputs.self` is not needed here because `self` is only read
  # through `inputs.self` and the builder takes it from there.
  consumerInputs = {
    coreOnly = true;
  }
  // lib.optionalAttrs (flakePartsSrc != null) { flake-parts = flakePartsSrc; };

  # Exercises every output name an extension registers, on one system, with
  # both kinds of host. `testhost` deliberately has no users so Home Manager is
  # not embedded in it; `homeonly` is what produces a standalone
  # homeConfigurations entry.
  baseModule = {
    imports = [
      ../../extensions/nixos
      ../../extensions/home-manager
      ../../extensions/overlays
      ../../extensions/packages
      ../../extensions/shells
    ];

    substrate.settings = {
      systems = [ system ];
      nixpkgsConfig.allowUnfree = true;
    };

    substrate.users.bob = { };

    substrate.hosts = {
      testhost = { inherit system; };
      homeonly = {
        usersOnly = true;
        users = [ "bob" ];
      };
    };

    # The minimum a NixOS host needs for `system.build.toplevel` to evaluate.
    substrate.modules.conformance.nixos = {
      boot.loader.grub.devices = [ "nodev" ];
      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
      };
      system.stateVersion = "25.11";
    };

    substrate.publish.overlays.greeting = _final: _prev: {
      greeting = "hi";
    };

    # A package entry receives the builder's per-system package set, so it is
    # the cheapest place to observe what the builder baked into it. Each probe
    # is its own entry: the packages output keeps derivations only, so a nested
    # attrset of them would be dropped.
    substrate.publish.packages = {
      greet =
        {
          pkgs,
          ...
        }:
        pkgs.writeShellScriptBin "greet" "echo hi";
      probeNixpkgsConfig =
        {
          pkgs,
          ...
        }:
        pkgs.writeText "nixpkgs-config" (if pkgs.config.allowUnfree then "unfree" else "default");
      probeOverlays =
        {
          pkgs,
          ...
        }:
        pkgs.writeText "overlays" (if pkgs ? greeting then "applied" else "missing");
      probePublished =
        {
          pkgs,
          ...
        }:
        # Published packages land under the configured namespace, not at the
        # top level of the package set.
        pkgs.writeText "published" (if pkgs.custom ? greet then "applied" else "missing");
    };

    substrate.publish.devShells.default =
      {
        pkgs,
        ...
      }:
      pkgs.mkShell {
        name = "conformance-shell";
      };
  };

  # Both input sets have to arrive as module arguments. Extensions that
  # destructure either one without a default turn its absence into a hard
  # error; these cases catch a builder that never passed it in the first place.
  inputArgModule =
    {
      inputs,
      ...
    }:
    {
      imports = [ baseModule ];
      substrate.settings.checks = [
        {
          name = "inputs-reach-modules";
          valid = inputs ? nixpkgs;
          warn = false;
          message = "inputs not passed as module args";
        }
        {
          name = "coreInputs-reach-modules";
          valid = inputs ? nixpkgs;
          warn = false;
          message = "coreInputs not passed as module args";
        }
      ];
    };

  failingCheckModule = {
    imports = [ baseModule ];
    substrate.settings.checks = [
      {
        name = "always-fails";
        valid = false;
        warn = false;
        message = "boom";
      }
    ];
  };

  warningCheckModule = {
    imports = [ baseModule ];
    substrate.settings.checks = [
      {
        name = "always-warns";
        valid = false;
        warn = true;
        message = "boom";
      }
    ];
  };

  # Modules must see the consumer's inputs even when role resolution happens
  # against a separate coreInputs set.
  separateInputsModule =
    {
      inputs,
      ...
    }:
    {
      imports = [ baseModule ];
      substrate.settings.checks = [
        {
          name = "modules-see-consumer-inputs";
          valid = inputs ? coreOnly;
          warn = false;
          message = "modules should see the consumer's inputs, not coreInputs";
        }
      ];
    };

  # The case table. Each entry is { extraArgs?, inputs?, module?, assertion };
  # `assertion` takes the built result and returns whether it conforms.
  caseTable = {
    globalOutputs = {
      assertion =
        result:
        result.nixosConfigurations.testhost.config.networking.hostName == "testhost"
        # The one output path `nix flake check` validates; if this is not a
        # derivation the flake is not usable.
        && lib.isDerivation result.nixosConfigurations.testhost.config.system.build.toplevel
        # The deployed system pins the nixpkgs it was built with. That comes
        # from the nixos extension, not from the builder, so it holds
        # everywhere.
        && result.nixosConfigurations.testhost.config.nixpkgs.flake.source != null
        && result.homeConfigurations ? "bob@homeonly";
    };

    overlaysAreFunctions = {
      assertion =
        result: lib.isFunction result.overlays.greeting && lib.isFunction result.overlays.packages;
    };

    # The overlays extension and the packages extension both register a
    # builder under `overlays`. Both results have to survive the merge or one
    # publisher silently disappears.
    sameNameOutputBuildersMerge = {
      assertion =
        result:
        builtins.attrNames result.overlays == [
          "greeting"
          "packages"
        ];
    };

    perSystemOutputs = {
      assertion =
        result:
        lib.isDerivation result.packages.${system}.greet
        && lib.isDerivation result.devShells.${system}.default
        && lib.isDerivation result.checks.${system}.substrate-config;
    };

    nixpkgsConfigReachesThePackageSet = {
      assertion = result: result.packages.${system}.probeNixpkgsConfig.text == "unfree";
    };

    settingsOverlaysReachThePackageSet = {
      assertion = result: result.packages.${system}.probeOverlays.text == "applied";
    };

    publishedPackagesReachThePackageSet = {
      assertion = result: result.packages.${system}.probePublished.text == "applied";
    };

    inputsReachModules = {
      module = inputArgModule;
      assertion = result: lib.isDerivation result.checks.${system}.substrate-config;
    };

    failingCheckThrows = {
      module = failingCheckModule;
      assertion = result: !(builtins.tryEval result.checks.${system}.substrate-config).success;
    };

    warningCheckPasses = {
      module = warningCheckModule;
      assertion = result: lib.isDerivation result.checks.${system}.substrate-config;
    };

    explicitCoreInputs = {
      extraArgs.coreInputs = stubInputs;
      inputs = consumerInputs;
      module = separateInputsModule;
      assertion =
        result:
        result.nixosConfigurations.testhost.config.networking.hostName == "testhost"
        && lib.isDerivation result.checks.${system}.substrate-config;
    };
  };

  cases = lib.concatMapAttrs (
    builderName: build:
    lib.mapAttrs' (
      caseName: spec:
      lib.nameValuePair "${builderName}.${caseName}" {
        check = spec.assertion (
          build (
            spec.extraArgs or { }
            // {
              inputs = spec.inputs or stubInputs;
            }
          ) (spec.module or baseModule)
        );
      }
    ) caseTable
  ) builders;
in
runTests "Builder Conformance Tests" cases
