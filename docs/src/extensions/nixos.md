# NixOS Extension

Registers a builder for the `nixosConfigurations` output name.

### Import

```nix
imports = [ inputs.substrate.substrateModules.nixos ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.nixosModules` | list | External NixOS modules to include |
| `substrate.hosts.<name>.usersOnly` | bool (default `false`) | Home-only host: no system built; users get host-scoped Home Manager configs |
| `substrate.hosts.<name>.nixpkgsConfig` | attrs | Extra nixpkgs config for this host's package set |

Host package sets are created once per distinct `(system, nixpkgs config)`
combination — `substrate.settings.nixpkgsConfig` merged with the host's
`nixpkgsConfig` — and handed to `nixosSystem` via `nixpkgs.pkgs`, so the
configuration's `pkgs` and the `pkgs` given to `extraArgsGenerators` are the
same value. Because the package set is fixed at creation, set nixpkgs config
through these options; modules that assign `nixpkgs.config` directly are
rejected by nixpkgs' own assertion. `nixpkgs.overlays` set by external
modules is still honored (appended onto the package set).

### Output

- `nixosConfigurations.<hostname>` - NixOS system configurations

### Usage

```nix
substrate.hosts.workstation = {
  system = "x86_64-linux";
  users = [ "alice" ];
};

substrate.modules.hardware.audio = {
  nixos = { ... }: {
    sound.enable = true;
    hardware.pulseaudio.enable = true;
  };
};
```

---

See the [extension index](index.md) for the composition hooks and the full list.
