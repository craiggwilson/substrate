# Devenv Extension

Defines devenv shells using the normal devenv module syntax, while keeping the
result portable across substrate builders.

### Import

```nix
imports = [ inputs.substrate.substrateModules.devenv ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.devenv.shells` | attrs of modules | Named devenv shell modules |

Each shell entry is a mergeable module body, so you can split a shell across
multiple files and Nix will combine them the same way it combines any other
module. Write the shell with regular devenv syntax: `packages`, `enterShell`,
`processes`, `services`, and so on.

### Output

- `devShells.<system>.<name>` - devenv shells built from the configured module

### Usage

```nix
substrate.devenv.shells.default = {
  packages = [ pkgs.git pkgs.hello ];

  enterShell = ''
    hello
  '';
};
```

Because substrate builds the shell with the same per-system `pkgs` it uses for
the rest of the system outputs, packages from substrate overlays are available
to the devenv module as normal `pkgs` values.

---

See the [extension index](index.md) for the composition hooks and the full list.
