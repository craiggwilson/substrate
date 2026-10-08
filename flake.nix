{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  # Dev/test dependency: the jail extension's integration tests run against
  # the real jail.nix. Consumers provide their own input; the jail extension
  # resolves it by role via substrate.lib.resolveInput.
  inputs.jail-nix.url = "sourcehut:~alexdavid/jail.nix";
  # Formatter/linter for `nix fmt` and the fmt check below.
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";

  outputs =
    {
      self,
      nixpkgs,
      jail-nix,
      treefmt-nix,
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

      # The book, with the option reference generated from the module system and
      # dropped in ahead of the build. Generating it here rather than checking in
      # a copy is the point: the reference cannot describe an option that no
      # longer exists.
      #
      # The link checker runs as a separate step rather than as an mdbook
      # preprocessor, because mdBook discards a preprocessor's exit code: as a
      # preprocessor the check would report nothing and still pass. Run
      # standalone, its failure is a real failure. See docs/book.toml.
      docsBook =
        pkgs:
        let
          optionReference = pkgs.writeText "options.md" (import ./docs/gen/options.nix { inherit pkgs; });
          src = pkgs.runCommand "substrate-docs-src" { } ''
            mkdir -p $out
            cp -r ${./docs}/. $out
            # Store paths arrive read-only, and reference/ holds nothing in the
            # source tree because the generated chapter is the only file in it.
            chmod -R u+w $out
            mkdir -p $out/src/reference
            cp ${optionReference} $out/src/reference/options.md
          '';
        in
        pkgs.runCommand "substrate-docs"
          {
            nativeBuildInputs = [
              pkgs.mdbook
              pkgs.mdbook-linkcheck2
              # linkcheck2 builds an HTTP client when it starts, even with --files
              # naming no file to fetch, and does not survive the unwrap without a
              # trust store. The build sandbox is what keeps a web link from
              # actually going out.
              pkgs.cacert
            ];
          }
          ''
            mdbook build ${src} -d $out
            # -f names no file, so no external link is fetched and the check needs
            # no network. Internal links are checked in every file regardless.
            mdbook-linkcheck2 --standalone --no-cache --files=__no_web_links__ ${src}
          '';
      # Formatter for `nix fmt` and the fmt check below. nixfmt only: deadnix
      # and statix were tried and dropped — their "fix" modes rewrite code
      # (removing unused lambda parameters), which changes semantics.
      treefmt =
        system:
        treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        };
    in
    (import ./.)
    // {
      formatter = forAllSystems (pkgs: (treefmt pkgs.system).config.build.wrapper);

      packages = forAllSystems (pkgs: {
        docs = docsBook pkgs;
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.mdbook
            pkgs.mdbook-linkcheck2
          ];
        };
      });

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
          builders-raw-test = mkTestWith "raw-test" { nixpkgsSrc = nixpkgs; } ./tests/builders/raw-test.nix;

          # Docs. Not a mkTest: there is no test file, and building the book
          # already fails on a chapter missing from SUMMARY.md or on a broken
          # cross-reference, because create-missing and the link checker are on.
          docs = docsBook pkgs;

          # Formatting/linting. Runs the same tools as `nix fmt`.
          fmt = (treefmt pkgs.system).config.build.check self;
        }
      );
    };
}
