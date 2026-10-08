{ stdenvNoCC }:
stdenvNoCC.mkDerivation {
  pname = "hello-package";
  version = "1.0";

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out
    touch $out/hello-package
  '';
}
