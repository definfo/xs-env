{
  description = "Nix devshells for XiangShan";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/be9e214982e20b8310878ac2baa063a961c1bdf6?narHash=sha256-HM791ZQtXV93xtCY%2BZxG1REzhQenSQO020cu6rHtAPk%3D";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/release-25.05";
  };

  outputs =
    { nixpkgs, nixpkgs-stable, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate =
          pkg:
          builtins.elem (nixpkgs.lib.getName pkg) [
            "espresso"
          ];
      };
      pkgs-stable = import nixpkgs-stable {
        inherit system;
      };

      inherit (pkgs-stable) pypy3;
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          # === tool ===
          wget
          git
          tmux
          curl
          time

          # === runtime ===
          python3
          python3Packages.psutil # for XiangShan/scripts/xiangshan.py
          # openjdk
          graalvmPackages.graalvm-ce

          # === toolchain ===
          gcc # host toolchain
          pkgsCross.riscv64.buildPackages.gcc # riscv64-unknown-elf-xxx toolchain
          llvm # for pgo
          clang
          gnumake # make
          dtc # device tree compiler
          flex
          autoconf
          bison
          # override mill & verilator to use our version
          (mill.overrideAttrs (
            finalAttrs: previousAttrs: {
              version = "0.12.15";
              src = fetchurl {
                url = "https://repo1.maven.org/maven2/com/lihaoyi/mill-dist/${finalAttrs.version}/mill-dist-${finalAttrs.version}.exe";
                hash = "sha256-6hu6AeIg9M4guzMyR9JUor+bhlVMEMPX1+FmQewKdtg=";
              };
            }
          ))
          (verilator.overrideAttrs (
            finalAttrs: previousAttrs: {
              version = "5.028";
              VERILATOR_SRC_VERSION = "v${finalAttrs.version}";
              src = fetchFromGitHub {
                owner = "verilator";
                repo = "verilator";
                rev = "v${finalAttrs.version}";
                hash = "sha256-YgK60fAYG5575uiWmbCODqNZMbRfFdOVcJXz5h5TLuE=";
              };
              doCheck = false;
            }
          ))

          # === sim ===
          espresso # ! Unfree
          (callPackage ./nix/circt.nix { })

          # === debug ===
          gtkwave

          # === lib ===
          readline
          SDL2
          zlib
          zstd
          sqlite

        ] ++ [
          # === Pydrofoil ===
          pypy3 
        ];
        shellHook = ''
          echo "=== Welcome to XiangShan devshell! ==="
          echo "Version info:"
          echo "- $(verilator --version)"
          echo "- $(mill --version | head -n 1)"
          echo "- $(gcc --version | head -n 1)"
          echo "- $(riscv64-unknown-linux-gnu-gcc --version | head -n 1)"
          echo "- $(java -version 2>&1 | head -n 1)"
          echo "You can press Ctrl + D to exit devshell."

          source ./env.sh
          ln -sf $(which espresso) ./XiangShan/src/main/resources/espresso
          ln -sf $(which firtool) $HOME/.cache/llvm-firtool/1.62.1/bin/firtool
          
          ln -sf ${pypy3}/lib/libpypy3.11-c.so libpypy3.11-c.so
          ln -sf ${pypy3}/lib/libpypy3.11-c.so libpypy3-c.so
          export LD_LIBRARY_PATH=$PWD
        '';
      };
    };
}
