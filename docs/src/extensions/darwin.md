# Darwin Extension

Registers a builder for the `darwinConfigurations` output name.

### Import

```nix
imports = [ inputs.substrate.substrateModules.darwin ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.darwin.modules` | list | External nix-darwin modules to include |
| `substrate.publish.darwinModules` | attrs | nix-darwin modules published under the `darwinModules` output |

Rewire substrate's pinned nix-darwin with
`inputs.substrate.inputs.nix-darwin.follows` or `.url`, the same way `nixpkgs`
and `home-manager` are rewired.

### Output

- `darwinConfigurations.<hostname>` - nix-darwin system configurations
- `darwinModules` - whatever is assigned to `substrate.publish.darwinModules`

### Darwin is a class, not a NixOS variant

A host is a darwin host when its system is one. That is the whole of the
routing: a host with a `*-darwin` system is built through `darwinSystem` and
every other host is skipped. A linux host produces nothing here, so importing
this extension in a linux-only configuration costs nothing.

The class distinction matters because a NixOS option does not exist in a
nix-darwin configuration and would fail rather than be ignored. A host declares
what belongs to it and gets exactly that:

```nix
substrate.modules.programs.zfs = {
  darwin = { services.zfs.enable = true; };   # built here
  nixos = { services.zfs.enable = true; };    # built on a NixOS host
};

substrate.modules.programs.blueman = {
  generic = { };                              # merged into every class
  nixos = { services.blueman.enable = true; };
};
```

A `darwin` module reaches a darwin host and a NixOS one never sees it.

### Usage

```nix
substrate.hosts.apple-silicon = {
  system = "aarch64-darwin";
  users = [ "alice" ];
};
```

Home Manager reaches darwin hosts the same way it reaches NixOS ones: this
extension declares a `contributors` entry targeting the `darwin` class, so
nothing here has to know the home-manager extension exists. Users of a
home-only host get a standalone configuration either way.

### What this does not cover

CI is linux, so this extension's tests assert the shape of what a darwin host
produces — which hosts are routed, which classes reach them, which
contributions load — rather than a built system. Building one is the first
thing to try on real hardware.

---

See [Publishing](../reference/publishing.md) for how a publish key becomes an
output, and the [extension index](index.md) for the composition hooks and the
full list.