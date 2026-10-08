# Overlays Extension

Manages nixpkgs overlays.

### Import

```nix
imports = [ inputs.substrate.substrateModules.overlays ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.overlays.internal` | list | Overlays applied to the package sets substrate builds, but not published |
| `substrate.overlays.publish` | attrs of overlay | Named overlays exposed for external reuse |

`substrate.settings.overlays` is core: builders bake it into every package set
substrate creates, so it exists whether or not this extension is loaded. The
extension prepends `internal` and `publish` to it and publishes `publish` under
the `overlays` output — import it when you want overlays published, not just
applied.

### Usage

```nix
substrate.overlays = {
  internal = [
    (final: prev: {
      myPackage = prev.callPackage ./pkgs/my-package { };
    })
  ];

  publish.default = inputs.some-flake.overlays.default;
};

substrate.settings.overlays = [
  (final: prev: {
    # User overlays still fit here.
  })
];
```

Published overlays are also exposed as the flake output `overlays.<name>`.

---

See the [extension index](index.md) for the composition hooks and the full list.
