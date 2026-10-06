# Home Manager Extension

Registers a builder for the `homeConfigurations` output name.

### Import

```nix
imports = [ inputs.substrate.substrateModules.home-manager ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.homeManagerModules` | list | External HM modules to include |
| `substrate.users.<name>.nixpkgsConfig` | attrs | Extra nixpkgs config for this user's host-scoped package sets (merged under the host's) |

Host-scoped builds import a package set with
`substrate.settings.nixpkgsConfig` merged with the user's `nixpkgsConfig` and
the host's. Users on system hosts share the host's package set instead (HM
`useGlobalPkgs`).

### Output

- `homeConfigurations.<user>@<host>` - Home Manager for users of `usersOnly` hosts.
  There is no host-less variant: users of system hosts are delivered through
  NixOS integration.

### NixOS Integration

When the NixOS extension is also loaded, this extension automatically
integrates Home Manager into every host configuration by registering a
`class = "nixos"` contributor (`home-manager.users.<name>` etc. with your
`homeManager`-class modules). The nixos extension has no knowledge of this
integration; it simply appends the contributors whose class it speaks.

### Usage

```nix
substrate.users.alice = {
  system = "x86_64-linux";
};

substrate.modules.programs.git = {
  homeManager = { ... }: {
    programs.git.enable = true;
  };
};
```

---

See the [extension index](index.md) for the composition hooks and the full list.
