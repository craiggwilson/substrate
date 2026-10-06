# Creating Custom Extensions

An extension is an ordinary module. What makes it an extension is that it writes
into substrate's namespaces rather than describing a host or user.

```nix
# extensions/my-extension/default.nix
{ lib, config, ... }:
{
  # Add new options
  options.substrate.settings.myOption = lib.mkOption {
    type = lib.types.str;
    default = "value";
    description = "My custom option";
  };

  # Add to supported classes (if adding a new class)
  config.substrate.settings.supportedClasses = [ "myClass" ];

  # Register output builders (global = once; perSystem = once per system)
  config.substrate.outputs.perSystem.myOutput = [
    {
      build =
        { pkgs, system, substrate, ... }:
        {
          # Return attrset to merge into this output name
        };
    }
  ];

  # Register a finder
  config.substrate.moduleFinders.my-finder.find =
    _cfgs:
    # Return list of modules
    [ ];

  # Push modules into builds (consumed by the builder for the declared class,
  # blind to the producing extension)
  config.substrate.settings.contributors = [
    {
      class = "nixos";
      contribute =
        { inputs, hostname, hostcfg, userConfigs, ... }:
        [
          # Return modules to append to each nixos configuration
          { }
        ];
    }
  ];
}
```

Export in `default.nix`:
```nix
{
  # ...existing exports...
  substrateModules = {
    # ...existing modules...
    my-extension = import ./extensions/my-extension;
  };
}
```

---

See the [extension index](index.md) for the composition hooks and the full list.
