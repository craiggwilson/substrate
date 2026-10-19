# Den Comparison

Den is one of the clearest points of comparison for substrate. We like it, we
learned from it, and substrate deliberately chooses a different shape.

This page is here to document that difference honestly: where Den is ahead of us,
where substrate is ahead of Den, and where the two projects are solving the same
problem with different tradeoffs.

## What Den Has That Substrate Does Not

Den’s public docs describe a broader framework surface than substrate currently
ships. Three things we used to list here are no longer gaps:

- **Darwin support.** Substrate has `substrateModules.darwin`, its own class
  alongside NixOS and home-manager, publishing `darwinModules` through the same
  core mechanism as every other key.
- **Namespaces for publishing aspect libraries.** `substrate.publish.substrateModules`
  is a marker that a module tree is a library, and a consumer assigns it
  straight into `substrate.modules`, which merges. The tree *is* the namespace,
  so there is no namespace machinery to learn. See
  [Publishing](reference/publishing.md).
- **Without-flake workflows.** `build.raw` and `build.flake` are the same
  function, so a non-flake `default.nix` and a `flake.nix` reach the same code.

What remains:

- **Aspect-first composition.** Den makes aspects the primary unit. One aspect
  can carry NixOS, Darwin, home-manager, or custom-class config in a single
  object, with nested aspects and `includes` forming a DAG.
- **Schema modules for hosts, users, and homes.** Den has `den.schema.*` base
  modules with freeform metadata and shared defaults that aspects can read.
- **Policies and entity topology.** Den exposes a policy pipeline for how
  entities fan out, including derived entity kinds and custom resolution
  behavior.
- **Custom classes as a first-class concept.** Den advertises custom classes,
  class modules, and batteries that can introduce new entity kinds and module
  systems. We have the mechanism — `supportedClasses` plus one output builder —
  and now the `darwin` extension as a worked example, but not the documentation
  or the batteries.
- **Diagrams and resolution graph tooling.** Den renders its resolution graph
  into Mermaid, GraphViz, PlantUML and more. The `explain` output answers the
  same question in structured data — what each host got, and what the finder
  filtered out — but does not render it as a picture.
- **Quirks.** Structured data many aspects contribute to that one consumer
  assembles, without producers knowing who consumes them. We lean on
  aggregating NixOS options instead.


## Gaps We Have Partly Covered

Substrate does not try to clone Den one feature at a time, but a few pieces move
in a similar direction:

- **`includes`** gives us explicit graph-based composition, which is the closest
  thing we have to Den’s aspect DAG.
- **`substrate.publish`** gives us one namespace for everything a configuration
  exposes, and `substrate.settings.publishers` is the registry that turns a key
  into an output.
- **`extraArgsGenerators` and contributors** cover a lot of the same extension
  pressure that Den solves with policies and batteries.
- **`tags` and `includes`** together cover two different selection styles, one
  categorical and one explicit.

Several of the remaining ones are renames of things we already ship, which is
worth writing down because the gap reads much larger from outside than it is:

| Den | Substrate |
|-----|-----------|
| aspect | a node of the `substrate.modules` tree |
| `os` class | the `generic` class, merged into every class |
| parametric aspects (`{ host, ... }:`) | `extraArgsGenerators`, which already hands every module `{ hostcfg, usercfg, inputs, pkgs }` |
| mutual providers | `settings.contributors` with `class = "nixos"` |
| batteries | contributors plus push registries like `wrappers.contributors` |
| `forward` battery | a `contribute` function returning a module |
| custom classes | `settings.supportedClasses` plus one output builder |
| aspects / namespaces | `substrate.publish` ([Publishing](reference/publishing.md)) |
| diagrams | the `explain` output ([Core Concepts](concepts.md)) |

If we wanted to narrow the remaining gap further, the obvious missing ideas
from Den are richer entity/schema layers — we have exactly two entity kinds,
hosts and users, both fixed — and quirks, which let many aspects contribute
structured data that one consumer assembles without knowing who produced it.

## What Substrate Has That Den Does Not

Substrate is intentionally narrower in a few places, but that narrowness buys
some useful things:

- **Pluggable finders are a core concept.** Substrate lets the selection model
  itself be swapped out. `tags` and `includes` are mutually exclusive by design.
- **A flatter module tree.** Substrate allows arbitrary intermediate nodes in the
  module tree and treats leaf detection as a simple class-key check. The cost is
  that a node under an unregistered class is indistinguishable from a grouping
  node, so a module written for a class whose extension is not imported would be
  dropped silently; a reachability check reports it.
- **No mandatory framework layer.** The extension surface is small and explicit;
  a builder is just a `lib` plus a shape.
- **Plain module portability.** A leaf module can stay usable outside substrate
  if it only depends on ordinary Nix module arguments.
- **Fewer moving parts.** There is no built-in policy engine, schema layer, or
  aspect namespace system to understand before writing a module.

## Why That Difference Exists

Den is optimized for a richer, more opinionated framework around aspects,
entity topology, and cross-platform configuration.

Substrate is optimized for a smaller core: a module tree, a finder, and a set of
extensions that stay close to ordinary Nix modules. That makes it easier to drop
in to an existing flake, easier to reason about, and easier to extend without
accepting a large framework surface.

In practice, that means we do not view Den as something to outgrow or replace.
It is a strong design in a different part of the tradeoff space, and this page is
our way of acknowledging the overlap without pretending the two projects are the
same thing.

## Short Version

- Den has more framework surface, more built-in structure, and broader platform
  coverage.
- Substrate has a smaller core, a flatter tree, and a more explicit extension
  model.
- The `includes` extension is our closest analogue to Den’s aspect graph, but it
  is still only one part of substrate’s model.
