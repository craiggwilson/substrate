# Types Extension

A place to define types once and share them across modules.

### Import

```nix
imports = [ inputs.substrate.substrateModules.types ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.types` | attrsOf (functionTo optionType) | Named types. Each takes a single `lib` argument |

### Usage

```nix
substrate.types = {
  # Takes lib, returns a type usable by mkOption
  hostname = lib: lib.types.strMatching "^[a-z0-9-]+$";
};
```

Another extension then reads it as `config.substrate.types.hostname`, so the
validation lives in one place rather than being restated per module.

---

See the [extension index](index.md) for the composition hooks and the full list.
