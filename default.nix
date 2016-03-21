with import <nixpkgs> {};

stdenv.mkDerivation {
  name = "warbo-utilities";
  src  = ./.;

  buildPhase   = "";
  installPhase = ''
    mkdir -p "$out/bin"
    for DIR in svn system web git development
    do
        cp "$DIR/"* "$out/bin/"
    done
  '';
}
