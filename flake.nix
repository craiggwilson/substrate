{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  # Dev/test dependency: the jail extension's integration tests run against
  # the real jail.nix. Consumers provide their own input; the jail extension
  # resolves it by role via substrate.lib.resolveInput.
  inputs.jail-nix.url = "sourcehut:~alexdavid/jail.nix";

  outputs =
    {
      self,
      nixpkgs,
      jail-nix,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    (import ./.)
    // {
      checks = forAllSystems (
        pkgs:
        let
          mkTestWith =
            name: extraArgs: testFile:
            let
              testResults = import testFile ({ inherit pkgs; } // extraArgs);
            in
            pkgs.runCommand "substrate-${name}" { } ''
              if ${pkgs.lib.boolToString testResults.allPassed}; then
                echo "All tests passed!"
                echo "${testResults.summary}"
                touch $out
              else
                echo "Tests failed!"
                echo "${testResults.summary}"
                exit 1
              fi
            '';
          mkTest = name: mkTestWith name { };
        in
        {
          # Core tests
          core-modules-test = mkTest "modules-test" ./tests/core/modules-test.nix;
          core-lib-test = mkTest "lib-test" ./tests/core/lib-test.nix;
          core-hosts-users-test = mkTest "hosts-users-test" ./tests/core/hosts-users-test.nix;
          core-overlays-packages-test = mkTest "overlays-packages-test" ./tests/core/overlays-packages-test.nix;
          core-finders-test = mkTest "finders-test" ./tests/core/finders-test.nix;
          core-outputs-test = mkTest "outputs-test" ./tests/core/outputs-test.nix;

          # Extension tests
          extensions-tags-test = mkTest "tags-test" ./tests/extensions/tags-test.nix;
          extensions-home-manager-test = mkTest "home-manager-test" ./tests/extensions/home-manager-test.nix;
          extensions-jail-test = mkTestWith "jail-test" {
            jailNix = jail-nix;
          } ./tests/extensions/jail-test.nix;
          extensions-secrets-test = mkTest "secrets-test" ./tests/extensions/secrets-test.nix;
          extensions-wrappers-test = mkTest "wrappers-test" ./tests/extensions/wrappers-test.nix;

          # Builder tests
          builders-checks-test = mkTest "checks-test" ./tests/builders/checks-test.nix;
        }
      );
    };
}
