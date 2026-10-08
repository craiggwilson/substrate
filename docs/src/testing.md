# Testing

Substrate includes a comprehensive test suite. This guide covers running tests and writing new ones.

## Running Tests

Run all tests:

```bash
nix flake check
```

Run a specific test:

```bash
nix build .#checks.x86_64-linux.core-modules-test
```

List available checks:

```bash
nix flake show --json | jq '.checks'
```

## Test Structure

```
tests/
├── lib.nix                    # Shared test utilities
├── core/                      # Core module tests
│   ├── modules-test.nix
│   ├── lib-test.nix
│   ├── hosts-users-test.nix
│   ├── finders-test.nix
│   ├── outputs-test.nix
│   └── overlays-packages-test.nix
├── extensions/                # Extension tests
│   ├── tags-test.nix
│   ├── home-manager-test.nix
│   ├── bubblewrap-test.nix
│   ├── secrets-test.nix
│   └── wrappers-test.nix
└── builders/                  # Builder tests
    └── checks-test.nix
```

Every file listed here is wired into `flake.nix` as a check. There are twelve:
six core, five extension, one builder.

## Test Library

The test library (`tests/lib.nix`) provides utilities for writing tests:

```nix
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib evalSubstrate runTests;
in
runTests "My Tests" { }
```

### Available Functions

| Function | Description |
|----------|-------------|
| `runTests` | Run a test suite and return `{ results, allPassed, summary }` |
| `runTest` | Run a single `{ name, check }` and return its result |
| `evalSubstrate` | Evaluate substrate with core modules |
| `evalSubstrateExtended` | Evaluate with hosts/users/checks |
| `mkEvalSubstrate` | Create a custom evaluator from a base module list |
| `classEval` | Evaluate a target configuration as a builder would build it, consuming only the contributions for `class` |
| `classWrap` | Make one `wrap.package` call from a module of the target configuration, the way a real module sees it |
| `coreModules` | List of core module paths |
| `extendedCoreModules` | Core modules plus hosts/users/checks |
| `minimalCoreModules` | Settings, lib, modules and finders only |
| `mkSummary` | Render results as the text `runTests` prints |
| `lib` | `pkgs.lib`, re-exported for convenience |

`classEval` and `classWrap` take the evaluation and return a fresh
`lib.evalModules` result, so a contribution cannot pass a test that no builder
would actually load.

## Writing Tests

### Basic Test Structure

```nix
# tests/core/my-test.nix
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib evalSubstrate runTests;

  tests = {
    testName = {
      check =
        let
          eval = evalSubstrate [
            {
              # Test configuration
              config.substrate.modules.test = {
                nixos = { };
              };
            }
          ];
        in
        # Boolean expression - true means pass
        eval.config.substrate.modules.test ? nixos;
    };

    anotherTest = {
      check =
        let
          result = builtins.tryEval (
            let
              eval = evalSubstrate [
                {
                  # Invalid: systems is a list of strings
                  config.substrate.settings.systems = "not-a-list";
                }
              ];
            in
            builtins.deepSeq eval.config.substrate.settings.systems true
          );
        in
        # Test that evaluation fails
        !result.success;
    };
  };
in
runTests "My Test Suite" tests
```

### Testing with Extensions

```nix
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib mkEvalSubstrate runTests;

  # Custom evaluator with specific modules
  evalSubstrate = mkEvalSubstrate [
    ../../core/settings.nix
    ../../core/lib.nix
    ../../core/modules.nix
    ../../core/finders.nix
    ../../core/hosts.nix
    ../../core/users.nix
    ../../extensions/overlays/default.nix
    ../../extensions/packages/default.nix
    ../../core/checks.nix
    ../../extensions/tags/default.nix
  ];

  tests = {
    tagsWork = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags = [ "core" ];
              config.substrate.modules.test = {
                nixos = { };
                tags = [ "core" ];
              };
            }
          ];
        in
        eval.config.substrate.modules.test.tags == [ "core" ];
    };
  };
in
runTests "Extension Tests" tests
```

### Testing Evaluation Failures

```nix
tests = {
  invalidConfigFails = {
    check =
      let
        result = builtins.tryEval (
          let
            eval = evalSubstrate [
              {
                # Invalid configuration
                config.substrate.hosts.myhost = {
                  users = [ "nonexistent" ];  # User doesn't exist
                };
              }
            ];
          in
          builtins.deepSeq eval.config.substrate.hosts.myhost.users true
        );
      in
      # Should fail because user doesn't exist
      !result.success;
  };
};
```

### Testing Finders

```nix
tests = {
  finderFiltersCorrectly = {
    check =
      let
        eval = evalSubstrate [
          {
            config.substrate.settings.tags = [ "core" "extra" ];
            config.substrate.modules.included = {
              nixos = { };
              tags = [ "core" ];
            };
            config.substrate.modules.excluded = {
              nixos = { };
              tags = [ "extra" ];
            };
            config.substrate.users.testuser = {
              tags = [ "core" ];
            };
          }
        ];
        found = eval.config.substrate.moduleFinders.by-tags.find [
          eval.config.substrate.users.testuser
        ];
      in
      lib.length found == 1;
  };
};
```

## Registering Tests

Add new tests to `flake.nix`. There are two helpers: `mkTest` for a test that
needs nothing but `pkgs`, and `mkTestWith` for one that needs extra arguments —
the jail test, for example, has to be handed the real `jail.nix`.

```nix
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
    # Existing tests
    core-modules-test = mkTest "modules-test" ./tests/core/modules-test.nix;
    extensions-bubblewrap-test = mkTestWith "bubblewrap-test" { jailNix = jail-nix; } ./tests/extensions/bubblewrap-test.nix;

    # Add your new test
    my-new-test = mkTest "my-new-test" ./tests/core/my-new-test.nix;
  }
);
```

## Test Patterns

### Pattern: Test Option Defaults

```nix
defaultsAreCorrect = {
  check =
    let
      eval = evalSubstrate [ ];
    in
    eval.config.substrate.settings.systems == [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-darwin"
      "x86_64-linux"
    ];
};
```

### Pattern: Test Option Merging

```nix
optionsMerge = {
  check =
    let
      eval = evalSubstrate [
        { config.substrate.settings.tags = [ "a" ]; }
        { config.substrate.settings.tags = [ "b" ]; }
      ];
    in
    lib.length eval.config.substrate.settings.tags == 2;
};
```

### Pattern: Test Type Validation

```nix
typeValidationWorks = {
  check =
    let
      result = builtins.tryEval (
        let
          eval = evalSubstrate [
            {
              # Invalid type - should fail
              config.substrate.settings.systems = "not-a-list";
            }
          ];
        in
        builtins.deepSeq eval.config.substrate.settings.systems true
      );
    in
    !result.success;
};
```

## Debugging Tests

### Print Intermediate Values

```nix
testWithDebug = {
  check =
    let
      eval = evalSubstrate [ ... ];
      found = eval.config.substrate.moduleFinders.all.find [ ];
      # Use trace for debugging
      _ = builtins.trace "Found ${toString (lib.length found)} modules" null;
    in
    lib.length found == 2;
};
```

### Evaluate Interactively

```bash
nix repl
:lf .
:p (import ./tests/core/modules-test.nix { pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux; }).results
```
