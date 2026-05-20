{
  description = "Graphify with extras: pdf, office, mcp, svg, bedrock, sql (pinned version)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        graphifyVersion = "0.8.13";
      in {
        devShells.default = pkgs.mkShellNoCC {
          name = "graphify-with-extras";

          buildInputs = with pkgs; [
            python312
            uv
            # System libraries needed by the extras
            pkg-config
            cairo
            pango
            harfbuzz
            fontconfig
            freetype
            libxml2
            libxslt
            poppler
            # For Office file support (optional)
            libreoffice
          ];

          shellHook = ''
            echo "🚀 Graphify Nix devShell ready"
            echo "   Version locked → graphifyy ${graphifyVersion}"
            echo "   Extras: pdf, office, mcp, svg, bedrock, sql"
            echo ""

            # Create venv if it doesn't exist
            if [ ! -d .venv ]; then
              uv venv --seed
            fi

            source .venv/bin/activate

            # Install/upgrade to exact pinned version with all requested extras
            uv pip install --upgrade "graphifyy[${extras}]=${graphifyVersion}"

            echo "✅ graphifyy ${graphifyVersion} with extras installed"
            echo "Run: graphify --help"
            echo "For GovCloud Bedrock: ensure AWS credentials + AWS_REGION=us-gov-west-1 (or east-1)"
          '';
        };
      });
}
