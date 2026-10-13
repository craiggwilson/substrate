# Capabilities Extension

Selects modules by what they `provide` and what they `require`, rather than by tags.

This is an alternative to the [tags extension](tags.md). The two solve similar problems
and both use `:` in names, but they are **not** interchangeable and `:` means something
different in each. Read [How this differs from tags](#how-this-differs-from-tags) before
choosing one.

### Import

```nix
imports = [ inputs.substrate.substrateModules.capabilities ];
```

Do not import this alongside the tags extension — both set `substrate.settings.modulesFinder`.

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.hosts.<name>.requires` | list of string | Capabilities this host needs |
| `substrate.users.<name>.requires` | list of string | Capabilities this user needs |
| `substrate.modules.<path>.provides` | list of string | Capabilities this module offers |
| `substrate.modules.<path>.requires` | list of string | Capabilities this module needs |
| `substrate.settings.capabilities.separator` | string | Character separating capability levels (default `:`) |

## The model

Hosts and users are the **roots**. Together their `requires` form one set — the
*required set* — and that set is the only thing selection looks at.

```nix
# modules/hardware/audio.nix
{
  config.substrate.modules.hardware.audio = {
    provides = [ "hardware:audio" ];

    # Declares the option a machine model will set
    generic = { lib, ... }: {
      options.hdwlinux.hardware.audio.soundcard = lib.mkOption { type = types.pcicard lib; };
    };

    nixos = { ... }: { services.pipewire.enable = true; };
  };
}

# modules/hardware/models/dell-xps-15-9520.nix
{
  config.substrate.modules.hardware.models.dell-xps-15-9520 = {
    provides = [ "hardware:model:dell" ];

    # Naming the capability guarantees the audio module is loaded, so setting
    # its option below cannot fail.
    requires = [ "hardware:audio" "hardware:bluetooth" "hardware:graphics:nvidia" ];

    generic = { hdwlinux.hardware.audio.soundcard = { busId = "00:1f.3"; }; };
    nixos = { ... }: { };
  };
}

# modules/hosts/unsouled.nix
{
  substrate.hosts.unsouled = {
    system = "x86_64-linux";
    users = [ "craig@work" ];
    requires = [ "hardware:model:dell" "hardware:audio" "printing" ];
  };
}

# modules/users/craig.nix
{
  substrate.users."craig@work" = { requires = [ "users:craig" "vpn:corp" ]; };
}
```

## Selection

```
requiredSet = host.requires ∪ ⋃ { u.requires : u ∈ host.users }

repeat until no more modules join:
    include M when
        wants(M)  = it offers something a requirement in requiredSet selects
        admits(M) = its requires are all in requiredSet ∪ provided
    provided = ⋃ { provides(M) : M ∈ included }

providedCapabilities = provided
```

`provided` starts empty, so the first pass sees only what the roots named. Two gates,
moving differently:

- **`wants` reads `requiredSet` and never widens.** A module gets in by offering
  something a host or user actually asked for. Nothing that happens during resolution
  changes this, so a chain of extensions cannot run away: every included module traces
  back to a requirement.
- **`admits` reads `requiredSet ∪ provided`.** Once something is in the build, a module
  that only needed *that* becomes eligible.

Both sets grow monotonically and are bounded by the module set, so this converges and the
result does not depend on visit order.

### A requirement selects anything it prefixes

`core` selects `core:ssh` and `core:networking` and anything else under it, on `:`-boundaries
— `program` does not select `programsvc`. This is the *only* place prefixes do anything,
and only in one direction. Including a module that offers `programs:vscode` does not put
`programs` anywhere: there is no walking back up.

The boundary character is configurable. Set `substrate.settings.capabilities.separator` to
`.` and the pairing works on `programs.vscode` instead, with `:` no longer special:

```nix
substrate.settings.capabilities.separator = ".";
```

It affects selection only. Capability names are otherwise flat strings, and nothing is
inferred from a suffix.

### `requires` filters, it does not pull in

A module naming something no root named **and nothing provided yet** is left out. It is
not an error on its own, and nothing is loaded to satisfy it.

That is what makes a headless machine possible. Both editors and headless tools can offer
`programming`:

```nix
config.substrate.modules.programs.vscode = {
  provides = [ "programs:vscode" "programming" ];
  requires = [ "gui" ];          # an editor needs a desktop
  nixos = { ... }: { };
};

config.substrate.modules.programs.grep = {
  provides = [ "programs:grep" "programming" ];
  nixos = { ... }: { };
};
```

A server that requires only `programming` gets `grep`. `vscode` is not selected. A
workstation that also requires `gui` gets both. Neither case fails.

### Extensions arrive on their own

`admits` consulting `provided` is what lets a module extend something that was already
built, without a root naming it directly:

```nix
# required: [ "ai:clients" "programming" "gui" ]
programs.vscode      provides [ "programs:vscode" "programming" ]  requires [ "gui" ]
programs.vscode.mcp  provides [ "ai:clients" "programs:vscode:mcp" ] requires [ "programs:vscode" ]
```

`mcp` satisfies `wants` on `ai:clients` from the start, but it cannot `admit` until
`vscode` is in the build providing `programs:vscode`. It joins on the next pass. This
chains, so an extension of an extension arrives too.

Note it still has to satisfy `wants` — meeting its requirements is not enough on its own.
A module offering nothing reachable from `requiredSet` stays out however many of its
requirements happen to be satisfied.

### Modules that must load together

Co-location is the mechanism. Two modules that both offer `core:nix` are always included
together, because a requirement that selects either selects both. For an option another
module declares, follow the convention:

> A module that declares options should `provides` a capability for them. Modules that
> set those options should `requires` it.

## Failures

Only a requirement the roots named can go unmet, and only when nothing included covers it.
Two distinct messages:

```
substrate: capability resolution failed.

  Capability 'hardware:model:dell' is offered by 1 module(s), all filtered out;
  they require [hardware:audio].
```

```
  Capability 'hardware:audoi' is required but no module offers it.
```

The first means a dependency was not wired up — a missed `requires`, most likely. The
second means the name matches nothing, usually a typo. A capability that only entered
scope by being prefixed was never *required*, so a filtered `core:ssh` is silent.

## hasCapability

`hasCapability` asks what the build ended up containing, not what the roots asked for:

```nix
homeManager =
  { hasCapability, ... }:
  {
    xdg.configFile."foo" = lib.mkIf (hasCapability "users:craig") "…";
  };
```

If `programs:vscode` got included because something required `programming`, then
`hasCapability "programs:vscode"` is `true` even though no root named it. It is `false`
for `programs`, because prefixes are not walked backwards. A name in the required set that
nothing offers is also `false`, as is one only a filtered module would have provided.

Because `provided` accumulates what included modules offer — every alias, not just the
one that was wanted — this reflects the whole build, including extensions that arrived on
a later pass.

## Checks

Three checks:

- **`capability-resolution`** (error) — every host's requirements are covered by an
  included module.
- **`unused-modules`** (warning) — a module no host selects, listed with what it offers.
  Usually a requirement nobody asked for.
- **`self-referential-capabilities`** (warning) — a module requiring something only it
  provides. Satisfiable once a root names the capability, so it does not break
  resolution, but it almost always means a name is wrong and the requirement never
  catches what it was meant to.

## How this differs from tags

Both answer "which modules belong in this configuration", and both use `:` in names. The
resemblance is superficial in one important respect: **`:` is a hierarchy in tags, and in
capabilities it only prefixes for selection.**

| | Tags | Capabilities |
|---|---|---|
| Declared with | `tags` on every module and host | `provides` / `requires` |
| Matching | a module's tags intersect the host's | a requirement selects what a module offers |
| `a:b` vs `a` | `a:b` implies `a`, both ways | `a` selects `a:b`; nothing implies `a` |
| Host says | `tags = [ "hardware:dell" ]` | `requires = [ "hardware:model:dell" "hardware:audio" ]` |
| Naming the modules | never possible — tags are a property query | implicit in what each module `provides` |
| Extra vocabulary | tag catalogue, meta-tags, implications, `hasTag` | `provides`, `requires` |
| Missing dependency | a module silently does not load | error naming the capability and the blocking `requires` |
| Two providers | both load | both load |
| Category questions | yes — "every desktop module" | only via a `requires` name that prefixes them, e.g. `desktop` |

**A dependency is now named, not implied.** Under tags, a machine model module and the
audio module landed in the same configuration because two unrelated meta-tags happened to
match. Here the model says `requires = [ "hardware:audio" ]` and the pairing is a fact
anyone can read. A dependency nothing supplies is a build error naming it, rather than a
module that quietly fails to load on one machine.

**The roots still decide what is wanted.** Nothing built during resolution can widen
`requiredSet`. A module joins because it satisfies a requirement, and if it stops
satisfying one it stops joining.

**Which to choose.** Capabilities are a better fit when modules have hard dependencies on
each other, or when the same module has to work with and without something — an editor on
a headless server. Tags are a better fit when selection is about describing a machine's
character — "laptop", "headless", "desktop" — and you want broad sweeps by category.

## Gotchas

- **A capability alone does not make a module.** Substrate decides a tree node is a module
  by whether it has a class body (`generic`, `nixos`, or another supported class), not by
  whether it declares capabilities. A node with only `provides = [ … ]` is never selected.
- **`hasCapability` is prefix-blind.** It answers for exactly what a module declared, so
  a query has to name a capability something actually offers. `hasCapability "audio"` is
  false when the audio module offers `hardware:audio`.
- **Names are case-sensitive.** `hardware:audio`, `hardware` and `Hardware` are unrelated.
- **An empty `requires` on a host selects nothing.** Everything a configuration gets must
  be reachable from a host or user requirement.