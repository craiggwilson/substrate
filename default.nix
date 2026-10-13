let
  wrapBuilder =
    builder: args: module:
    let
      module' = {
        imports = [
          module
          ./core
        ];
      };
    in
    builder.build args module';

  plain = import ./builders/plain.nix;
in
{
  build = {
    with-flake-parts = wrapBuilder (import ./builders/flake-parts/default.nix);
    # One implementation, two names. `raw` is the entry point a non-flake
    # `default.nix` has always used; `flake` is the same function under the
    # name a `flake.nix` reaches for. See docs/src/builders.md.
    flake = wrapBuilder plain;
    raw = wrapBuilder plain;
  };
  substrateModules = {
    bubblewrap = import ./extensions/bubblewrap;
    devenv = import ./extensions/devenv;
    home-manager = import ./extensions/home-manager;
    nixos = import ./extensions/nixos;
    overlays = import ./extensions/overlays;
    packages = import ./extensions/packages;
    published-modules = import ./extensions/published-modules;
    secrets = import ./extensions/secrets;
    shells = import ./extensions/shells;
    tags = import ./extensions/tags;
    wrappers = import ./extensions/wrappers;
  };
}
