{ inputs, system }:

let
  pkgs = import inputs.nixpkgs {
    inherit system;
    overlays = [ 
      inputs.iohk-nix.overlays.crypto
      inputs.iohk-nix.overlays.haskell-nix-crypto
      inputs.haskell-nix.overlay
    ];
  };

  project = pkgs.haskell-nix.cabalProject' {
    src = ../.;
    compiler-nix-name = "ghc966";
    inputMap = {
      "https://chap.intersectmbo.org/" = inputs.CHaP;
    };
  };
in
{
  packages.default = project.hsPkgs.sc-testing-tools-tutorial.components.library;
  devShells.default = project.shellFor {
    packages = p: [ p.sc-testing-tools-tutorial ];
    withHoogle = false;
    nativeBuildInputs = [
      pkgs.cabal-install
      pkgs.pre-commit
    ];
    buildInputs = [ pkgs.lmdb ];
  };
}
