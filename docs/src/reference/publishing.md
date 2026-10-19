# Publishing

Publishing is how a configuration exposes something to consumers. It is core
vocabulary, beside `substrate.outputs`, because that is what it is: naming what
an output carries.

There is one namespace, `substrate.publish`, and one registry,
`substrate.settings.publishers`. An extension that wants to expose something
declares a key and registers where it lands; it never writes an output builder
itself.

## Publishing a module tree

This is the marker for "my module tree is a library another configuration can
consume". Everything in `substrate.modules` is a substrate module, but only what
is named here is meant to be read by someone else, so a configuration that
publishes nothing can still use its tree freely for itself.

```nix
{ config, ... }: {
  config.substrate.modules.programs.git.nixos = { programs.git.enable = true; };

  # The whole tree is consumable.
  substrate.publish.substrateModules = config.substrate.modules;
}
```

A consumer assigns it straight into its own tree:

```nix
substrate.modules = inputs.mylib.substrateModules;
```

`substrate.modules` is an attribute set of submodules, so the module system
does the merging. There is no namespace machinery to learn: the tree *is* the
namespace.

## Publishing modules for one class

An extension that owns a module system declares its own key, so the type at that
path is one the extension vouches for. `nixos`, `homeManager` and `darwin` each
declare `nixosModules`, `homeManagerModules` and `darwinModules`:

```nix
substrate.publish.nixosModules = {
  myModule = { config, pkgs, ... }: { programs.git.enable = true; };
};
```

A consumer takes it the same way a flake consumer takes any `nixosModules`
output:

```nix
nixosConfigurations.host = nixpkgs.lib.nixosSystem {
  modules = [ inputs.mylib.nixosModules.myModule ];
};
```

Assigning a key whose extension is not imported is an error naming the key,
rather than a value that quietly reaches no output.

## Publishing packages, overlays and shells

Same namespace, same registry:

```nix
substrate.publish.packages = { myPkg = ./pkgs/my-pkg.nix; };
substrate.publish.overlays.default = final: prev: { myPkg = final.callPackage ./pkgs/my-pkg.nix { }; };
substrate.publish.devShells.default = { pkgs, ... }: pkgs.mkShell { };
```

`packages` is built per system; `overlays` is built once. Which is which is
declared by the extension that owns the key, not chosen by the publisher.

## Adding a key

An extension publishing something new does three things, all in its own module
set:

```nix
{
  options.substrate.publish.widgets = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = { };
    description = "Widgets exposed to consumers under the `widgets` output.";
  };

  config.substrate = {
    settings.publishers.widgets = {
      scope = "perSystem";              # or "global"
      output = "widgets";
      build = { substrate, ... }: substrate.publish.widgets;
    };
  };
}
```

`build` receives the standard output-builder context, not a context of
publishing's own: `{ inputs, coreInputs, substrate }`, plus `{ pkgs, system }`
when the entry is `perSystem`. Reading the key off `substrate` means a publisher
never closes over `config`.

A key is one namespace reaching one output. A value that belongs under two
output names keeps its extra output builder directly, the way any module can —
published packages are the case that does this, contributing both the
`packages` output and a `packages` overlay under `overlays`.

## The explain output

Publishing answers "what did I hand out". The `explain` output answers the
other half — "what did each host get":

```console
$ nix eval .#explain --json | jq '.classes.nixos.igloo'
{
  "igloo": [ "programs/git", "services/blueman" ],
  "igloo+users": [ ... ],
  "igloo/alice": [ ... ]
}
```

`available` sits alongside it, listing everything the finder could have
returned. The difference between the two is what the finder filtered out, which
is otherwise invisible. See [Core Concepts](../concepts.md).