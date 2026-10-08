# Published Modules Extension

Publishes modules you have written under module output names, so other flakes
(or any other build system) can consume
them the same way they consume substrate's own extensions.

### Import

```nix
imports = [ inputs.substrate.substrateModules.published-modules ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.modules.publish.nixosModules` | attrsOf anything | Named NixOS modules, default `{}` |
| `substrate.modules.publish.homeManagerModules` | attrsOf anything | Named Home Manager modules, default `{}` |
| `substrate.modules.publish.substrateModules` | attrsOf anything | Named substrate modules, default `{}` |

### Output

Each namespace becomes a global output, but only if you set it — an empty
namespace is not emitted at all, so importing this extension costs nothing on
the outputs you don't use:

- `nixosModules.<name>`
- `homeManagerModules.<name>`
- `substrateModules.<name>`

### Usage

```nix
substrate.modules.publish = {
  nixosModules.my-module = ./modules/my-module.nix;
  homeManagerModules.my-home-module = ./modules/my-home-module.nix;
  substrateModules.my-substrate-extension = ./extensions/my-extension;
};
```

The types are deliberately loose (`anything`): a module cannot be type-checked
before it is evaluated, so substrate passes these through untouched and lets the
consumer's module system validate them.

---

See the [extension index](index.md) for the composition hooks and the full list.
