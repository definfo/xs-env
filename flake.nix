{
  description = "Nix devshells for XiangShan";

  inputs = {
    # nixpkgs.url = "github:NixOS/nixpkgs/be9e214982e20b8310878ac2baa063a961c1bdf6?narHash=sha256-HM791ZQtXV93xtCY%2BZxG1REzhQenSQO020cu6rHtAPk%3D";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    flake-root.url = "github:srid/flake-root";
    pydrofoil.url = "git+https://github.com/definfo/pydrofoil?ref=nix-support&submodules=1";
  };

  outputs =
    inputs@{ nixpkgs, flake-parts, ... }:
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
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.flake-root.flakeModule
      ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        # "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem =
        {
          config,
          self',
          lib,
          ...
        }:
        {
          devShells.default =
            let
              inherit (inputs.pydrofoil.packages.${system}) pydrofoil-riscv-plugin;
            in
            pkgs.mkShell {
              inputsFrom = [ config.flake-root.devShell ];
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

                # === Pydrofoil ===
                pydrofoil-riscv-plugin
                cachix
                patchelf
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

                apply_patch() {
                  local repo="$1"
                  local patch_file="$2"
                  if git -C "$repo" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
                    echo "Patch $(basename "$patch_file") already applied in $repo, skipping."
                  else
                    if git -C "$repo" apply --check "$patch_file" >/dev/null 2>&1; then
                      echo "Applying patch $(basename "$patch_file") in $repo..."
                      git -C "$repo" apply "$patch_file"
                    else
                      echo "ERROR: Patch $(basename "$patch_file") cannot be applied cleanly in $repo. Maybe it's already applied partially or there's a conflict?"
                      exit 1
                    fi
                  fi
                }
                apply_patch XiangShan/ $FLAKE_ROOT/patches/0001-add-pydrofoil-ref-model.patch
                apply_patch XiangShan/difftest/ $FLAKE_ROOT/patches/0002-add-pydrofoil-refproxy.patch

                ${pydrofoil-riscv-plugin}/bin/pypy3.11 pydrofoil_cffi_difftest.py && \
                  ln -sf difftest_pydrofoil_riscv.so pypy-c-pydrofoil-riscv.so
                patchelf --set-rpath ${pydrofoil-riscv-plugin}/bin difftest_pydrofoil_riscv.so
                export PYDROFOIL_HOME=$FLAKE_ROOT
              '';
            };
        };
    };
}
