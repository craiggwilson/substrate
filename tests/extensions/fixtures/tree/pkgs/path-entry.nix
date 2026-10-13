# A bare package file: the path-entry form. Substrate callPackage's it.
{ stdenvNoCC }:
stdenvNoCC.mkDerivation {
  pname = "path-entry";
  version = "1.0";

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out
    touch $out/path-entry
  '';
}
