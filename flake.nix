{
  description = "lldap packaged with buildRustPackage";

  inputs = {
    # You can bump this to a newer channel as needed
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; }; 
        lib = pkgs.lib;

        # Common native build inputs potentially required by crates
        commonNativeBuildInputs = with pkgs; [
          pkg-config
        ];

        # Common build inputs for linking (openssl, sqlite, etc.)
        commonBuildInputs = with pkgs; [
          openssl
          sqlite
          zlib
          # Add other libs as needed by features
        ];

        src = lib.cleanSourceWith {
          src = ./.;
          filter = path: type:
            # Include all source including Cargo.lock and vendored crates if any
            !lib.hasInfix "/.git/" path;
        };

        lldap = pkgs.rustPlatform.buildRustPackage {
          pname = "lldap";
          version = (builtins.fromTOML (builtins.readFile ./server/Cargo.toml)).package.version;

          inherit src;

          cargoLock = {
            lockFile = ./Cargo.lock;
            outputHashes = {
              "lber-0.4.3" = "sha256-smElQyP8aWlV+/GvaTAx+BJWRtzQuis4XOUCOgebEF4=";
              "yew_form-0.1.8" = "sha256-1n9C7NiFfTjbmc9B5bDEnz7ZpYJo9ZT8/dioRXJ65hc=";
            };
          };

          # The workspace default-member is server, which builds the "lldap" bin
          cargoBuildFlags = [ "-p" "lldap" "--locked" ];

          nativeBuildInputs = commonNativeBuildInputs;
          buildInputs = commonBuildInputs;

          # Ensure runtime libs are available
          OPENSSL_NO_VENDOR = 1;

          # set SQLITE feature expectations
          SQLITE3_LIB_DIR = pkgs.sqlite.out + "/lib";
          SQLITE3_INCLUDE_DIR = pkgs.sqlite.dev + "/include";

          # Propagate runtime paths for dynamic libs
          postInstall = ''
            # Ensure the binary is available as lldap in $out/bin
            if [ ! -e "$out/bin/lldap" ]; then
              echo "Expected lldap binary not found" 1>&2
              exit 1
            fi
          '';
        };
      in {
        packages = {
          inherit lldap;
          default = lldap;
        };
        apps.default = {
          type = "app";
          program = lib.getExe lldap;
        };
        devShells.default = pkgs.mkShell {
          buildInputs = commonBuildInputs ++ (with pkgs; [
            rustup
            cargo
            clippy
            rustfmt
            pkg-config
          ]);
          shellHook = ''
            echo "Entering lldap dev shell for ${system}"
          '';
        };
      }
    );
}
