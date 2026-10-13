# Devenv Extension

Builds shells with devenv, so a shell is a devenv module rather than an
`mkShell` call. One option, `substrate.devenv.shells`, names them; each name
becomes one `devShells` entry.

### Import

```nix
imports = [ inputs.substrate.substrateModules.devenv ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.devenv.shells` | attrs of entry | Named devenv shells |

An entry is a devenv module, in either of two shapes:

| Shape | Use it when |
|-------|-------------|
| An attribute set of devenv options | It needs nothing from the build |
| A function of devenv's module arguments | It needs `pkgs` — the normal case |

```nix
substrate.devenv.shells.default =
  {
    pkgs,
    ...
  }:
  {
    devenv.root = "/home/you/projects/thing";
    packages = [ pkgs.hello pkgs.git ];
    enterShell = "hello";
  };
```

Write a function entry as `{ pkgs, ... }: ...` so it survives additions to
devenv's argument set.

The function is called by devenv, so it receives devenv's arguments: `pkgs`,
`config`, `options`, `lib`, `inputs`, and your flake inputs by name. Substrate
never calls it, and `pkgs` is not a module argument of a substrate
configuration — a module of yours that writes `pkgs` directly fails.

That `pkgs` is the one substrate builds the rest of the system with, so
`settings.overlays` and `settings.nixpkgsConfig` already apply: a package from
an overlay is reachable as `pkgs.<name>` with nothing extra imported.

### One entry per shell

A function entry has to reach devenv unapplied. The moment any other module
defines anything about the same shell — an attribute set for the name, or one
nested option like `shells.default.enterShell` — the substrate module system
claims the function and calls it with substrate's own arguments instead of
devenv's. It fails with `attribute 'pkgs' missing`, at evaluation, naming
neither the module nor the option.

So: a function entry is the only definition of its name, or it is not a
function entry.

| Definitions of one name | Result |
|-------------------------|--------|
| One function entry | Reaches devenv and is applied there |
| Two attribute sets | Merged |
| An attribute set and nested options | Merged |
| Two different nested options | Merged |
| One option twice, with different values | Error: conflicting definitions |
| A function entry plus anything else | Error: `attribute 'pkgs' missing` |

Everything a shell needs therefore goes in the one entry. When a module tree
has to contribute to a shell, merge attribute sets instead: they are the shape
that merges, and they take no arguments, so they are for entries that do not
need `pkgs`.

### Output

- `devShells.<system>.<name>` — one devenv shell per name, for every system in
  `settings.systems`

### `devenv.root` is required

Pure evaluation cannot read the working directory, which is what devenv
defaults `devenv.root` to. A shell without it fails, when its derivation is
forced:

```
Failed assertions:
- devenv was not able to determine the current directory.
```

Set it to an absolute path. It is also where the shell writes: devenv creates
`$devenv.root/.devenv` on entry, so pointing it at a directory that does not
exist creates that directory. A shell whose toolchain is only useful inside a
checkout therefore points `devenv.root` at the checkout and checks for it in
`enterShell`.

Pure evaluation is what forces the option in the first place: `nix develop`
evaluates the flake with `builtins.getEnv "PWD"` returning `""`, which is what
devenv defaults the root to. An impure evaluation — `nix develop
--no-pure-eval`, or `nix print-dev-env --impure` — can see the working
directory, and a shell that wants both behaviours says so with a literal for
the case where it cannot:

```nix
devenv.root =
  let
    pwd = builtins.getEnv "PWD";
  in
  if pwd != "" then pwd else "/home/you";
```

Pure evaluation takes the literal, so the flake still evaluates to the same
shell on every machine. An impure one takes the directory you entered, which
puts `.devenv`, the runtime directory and the task cache beside the checkout
rather than in one place shared by every project. The cost is that an impure
entry creates `.devenv` in whatever directory you were standing in, so that
directory needs `.devenv*` ignored.

Note that direnv does not make evaluation impure for you: `use flake` runs
`nix print-dev-env` without `--impure`, so a shell entered by direnv takes the
literal branch.

### Conditional shells

`lib.mkIf` works around the set, or around a single entry, function or not:

```nix
substrate.devenv.shells = lib.mkIf (builtins.pathExists "${root}/mms") {
  mms =
    { pkgs, ... }:
    {
      devenv.root = "${root}/mms";
      packages = [ pkgs.bazelisk ];
    };
};
```

`builtins.pathExists` reads the filesystem under pure evaluation, so the entry
is published only where its project is checked out. Where the path is absent
the entry is undefined; where no shell at all is configured, there is no
`devShells` output.

### What ends up on `PATH`

The extension calls `devenv.lib.mkShell`, which is devenv's flake integration —
the mode where a shell is built from Nix instead of from `devenv.yaml`. Nothing
here runs the devenv CLI, and substrate does not install it. What the shell does
get:

| Command | What it is |
|---------|------------|
| `devenv` | A wrapper script from devenv's flake integration: `up`, `test`, `tasks`, `version`, and nothing else |
| `devenv-flake-up` | Starts `processes` in the foreground — what `devenv up` runs |
| `devenv-flake-test` | Runs `enterTest` |
| `devenv-flake-tasks` | Runs `tasks` |
| `process-compose` | The default process manager, which devenv adds to `packages` |
| anything in `scripts` | Each becomes a command of the same name |
| `devenv-tasks` | **Not** on `PATH`; devenv calls it by absolute path from `config.task.package` |

The three `devenv-flake-*` scripts are the substance the wrapper wraps. The
wrapper's only job is to re-enter the flake first — `nix develop .#<name>
--impure` — so the command runs against a freshly evaluated configuration. Two
things stop that from being a problem here, and the extension does both: each
shell passes its own name to devenv, so `<name>` is the shell you are in and
not `.#default`, and each shell sets `DEVENV_IN_DIRENV_SHELL`, which tells the
wrapper the shell is already entered. `devenv up` therefore does the obvious
thing. Running `devenv-flake-up` yourself skips the re-entry entirely.

### Tasks

Tasks are configuration, and they run. One runs at shell entry when it is
attached to `devenv:enterShell` — before it, or wanting to be run by it:

```nix
tasks."app:deps".exec = "npm ci";
tasks."app:deps".before = [ "devenv:enterShell" ];

tasks."app:migrate".exec = "./migrate";
tasks."app:migrate".wantedBy = [ "devenv:enterShell" ];
```

An unattached task is defined but idle until something selects it, by name:

```console
$ devenv tasks run app:migrate
```

That runs through the wrapper; `devenv-flake-tasks run app:migrate` is the same
thing without the re-entry, and takes no `--cache-dir` or `--runtime-dir` —
devenv passes them, from `$DEVENV_DOTFILE` and `$DEVENV_RUNTIME`. Task names
must be namespaced (`app:migrate`), which is devenv's rule, not substrate's.

### Processes

Processes run too, supervised by a process manager rather than by the CLI. With
no CLI version set, `process.manager.implementation` defaults to
`process-compose`, and devenv adds it to `packages` and turns each process into
a task of its own:

```nix
processes.db.exec = "exec postgres";
processes.db.ready.http.get.port = 5432;
```

`devenv up` starts the manager in the foreground and shuts it down on SIGINT or
SIGTERM. `scripts.up.exec = "exec devenv-flake-up"` publishes that same command
as `up`, without the re-entry. Neither needs the CLI.

A `ready` probe still works — devenv hands it to process-compose as its own
readiness probe — but a port is not allocated. `ports.<name>.value` is normally
resolved by incrementing `ports.<name>.allocate` until a port is free, and that
is CLI work: without it, `value` is just the number you declared.

One trap: the manager's state lives under `$DEVENV_RUNTIME`, and killing it
rather than stopping it — `timeout`, a closed terminal, a crash — leaves its
guardians behind. The next run then fails every process with `process <name> is
already managed`. Clear `$DEVENV_RUNTIME` and it starts clean.

### What still needs the CLI

Port auto-allocation, `process.proxy`, `devenv search`, containers, cloud, and
`devenv.yaml` itself — all of which belong to the CLI, which is not what runs
these shells.

Adding it to `packages` does not change that, and does not even get you the
command: devenv's wrapper is prepended to `PATH` when the shell is entered, so
`devenv` is the wrapper no matter what else is installed. The CLI does land in
the profile, at `$DEVENV_PROFILE/bin/devenv`, and runs from there — but it is
then a different program from this shell, reading `devenv.yaml` and evaluating
its own vendored configuration. Reach for it when you want a standalone devenv
project; it does not extend the shells substrate builds.

---

See the [extension index](index.md) for the composition hooks and the full list.