{ lib, ... }:
let
  overlayType = lib.types.functionTo (lib.types.functionTo lib.types.attrs);
in
{
  options.substrate.settings.overlays = lib.mkOption {
    type = lib.types.listOf overlayType;
    default = [ ];
    description = ''
      Overlays to apply to nixpkgs in every package set substrate creates
      (host and host-scoped user package sets). Each overlay is a function
      final: prev: { ... }.

      Core declares this because builders bake it into every package set they
      create. Extensions add to it the ordinary way — by assigning here — so
      they compose with whatever the user sets.
    '';
  };
}
