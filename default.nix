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
in
{
  build = {
    with-flake-parts = wrapBuilder (import ./builders/flake-parts/default.nix);
    raw = wrapBuilder (import ./builders/raw/default.nix);
  };
  substrateModules = {
    bubblewrap = import ./extensions/bubblewrap;
    home-manager = import ./extensions/home-manager;
    nixos = import ./extensions/nixos;
    overlays = import ./extensions/overlays;
    packages = import ./extensions/packages;
    published-modules = import ./extensions/published-modules;
    secrets = import ./extensions/secrets;
    shells = import ./extensions/shells;
    tags = import ./extensions/tags;
    types = import ./extensions/types;
    wrappers = import ./extensions/wrappers;
  };
}
