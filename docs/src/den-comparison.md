# Den Comparison

Den is one of the clearest points of comparison for substrate. We like it, we
learned from it, and substrate deliberately chooses a different shape.

This page is here to document that difference honestly: where Den is ahead of us,
where substrate is ahead of Den, and where the two projects are solving the same
problem with different tradeoffs.

## What Den Has That Substrate Does Not

Den’s public docs describe a broader framework surface than substrate currently
ships:

- **Aspect-first composition.** Den makes aspects the primary unit. One aspect
  can carry NixOS, Darwin, home-manager, or custom-class config in a single
  object, with nested aspects and `includes` forming a DAG.
- **Darwin support.** Den targets NixOS, nix-Darwin, and home-manager out of the
  box. Substrate currently covers NixOS and home-manager only.
- **Schema modules for hosts, users, and homes.** Den has `den.schema.*` base
  modules with freeform metadata and shared defaults that aspects can read.
- **Policies and entity topology.** Den exposes a policy pipeline for how
  entities fan out, including derived entity kinds and custom resolution
  behavior.
- **Custom classes as a first-class concept.** Den advertises custom classes,
  class modules, and batteries that can introduce new entity kinds and module
  systems.
- **Namespaces for publishing aspect libraries.** Den supports sharable aspect
  namespaces across flakes and non-flakes.
- **Diagrams and resolution graph tooling.** Den can render or describe the
  resolution graph for debugging and documentation.
- **Without-flake workflows as a first-class story.** Den explicitly documents
  non-flake usage alongside flake-parts support.

## Gaps We Have Partly Covered

Substrate does not try to clone Den one feature at a time, but a few pieces move
in a similar direction:

- **`includes`** gives us explicit graph-based composition, which is the closest
  thing we have to Den’s aspect DAG.
- **`published-modules`** gives us a way to publish reusable module trees under
  named outputs.
- **`extraArgsGenerators` and contributors** cover a lot of the same extension
  pressure that Den solves with policies and batteries.
- **`tags` and `includes`** together cover two different selection styles, one
  categorical and one explicit.

If we wanted to narrow the gap further, the most obvious missing ideas from Den
are aspect namespaces, richer entity/schema layers, and a more formal resolution
pipeline for non-NixOS classes.

## What Substrate Has That Den Does Not

Substrate is intentionally narrower in a few places, but that narrowness buys
some useful things:

- **Pluggable finders are a core concept.** Substrate lets the selection model
  itself be swapped out. `tags` and `includes` are mutually exclusive by design.
- **A flatter module tree.** Substrate allows arbitrary intermediate nodes in the
  module tree and treats leaf detection as a simple class-key check.
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
