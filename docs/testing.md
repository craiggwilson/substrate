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
├── lib.nix              # Shared test utilities
├── core/                # Core module tests
│   ├── modules-test.nix
│   ├── lib-test.nix
│   ├── hosts-users-test.nix
│   ├── finders-test.nix
│   └── overlays-packages-test.nix
├── extensions/          # Extension tests
│   ├── tags-test.nix
│   └── home-manager-test.nix
└── builders/            # Builder tests
    └── checks-test.nix
```

## Test Library

The test library (`tests/lib.nix`) provides utilities for writing tests:

```nix
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib evalSubstrate runTests;
in
# Use testLib functions
```

### Available Functions

| Function | Description |
|----------|-------------|
| `runTests` | Run a test suite and return results |
| `evalSubstrate` | Evaluate substrate with core modules |
| `evalSubstrateExtended` | Evaluate with hosts/users/checks |
| `mkEvalSubstrate` | Create custom evaluator with specific modules |
| `coreModules` | List of core module paths |
| `extendedCoreModules` | Core modules plus hosts/users/checks |

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
            # Expression that might fail
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
        found = eval.config.substrate.finders.by-tags.find [
          eval.config.substrate.users.testuser
        ];
      in
      lib.length found == 1;
  };
};
```

## Registering Tests

Add new tests to `flake.nix`:

```nix
checks = forAllSystems (
  pkgs:
  let
    mkTest = name: testFile:
      let
        testResults = import testFile { inherit pkgs; };
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
  in
  {
    # Existing tests
    core-modules-test = mkTest "modules-test" ./tests/core/modules-test.nix;
    
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
      found = eval.config.substrate.finders.all.find [ ];
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
