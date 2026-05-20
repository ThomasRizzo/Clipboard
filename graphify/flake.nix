{
  description = "Graphify (pinned + smart setup) with extras: pdf, office, mcp, svg, bedrock, sql";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        graphifyVersion = "0.8.13";
        extras = "pdf,office,mcp,svg,bedrock,sql";
      in {
        devShells.default = pkgs.mkShellNoCC {
          name = "graphify-with-extras";

          buildInputs = with pkgs; [
            python312
            uv
            # System dependencies for the requested extras
            pkg-config
            cairo
            pango
            harfbuzz
            fontconfig
            freetype
            libxml2
            libxslt
            poppler
            libreoffice
          ];

          shellHook = ''
            echo "🚀 Setting up Graphify environment..."
            echo "   • Pinned version : graphifyy == ${graphifyVersion}"
            echo "   • Extras         : ${extras}"
            echo ""

            # 1. Create venv if it doesn't exist
            if [ ! -d .venv ]; then
              echo "Creating virtual environment..."
              uv venv --seed
            fi

            # 2. Activate the venv
            source .venv/bin/activate

            # 3. Check if correct version is already installed
            if python -c "import graphifyy; import pkg_resources; print(pkg_resources.get_distribution('graphifyy').version)" 2>/dev/null | grep -q "^${graphifyVersion}$"; then
              echo "✅ Correct version of graphifyy (${graphifyVersion}) is already installed."
            else
              echo "Installing / upgrading graphifyy to exact pinned version..."
              uv pip install --upgrade \
                "graphifyy[${extras}]==${graphifyVersion}"
              echo "✅ Graphifyy successfully installed/updated!"
            fi

            echo ""
            echo "🎉 Graphify is ready!"
            echo "Available commands:"
            echo "   graphify --help"
            echo "   graphify install          # Register as AI coding skill (first time)"
            echo ""
            echo "💡 AWS GovCloud / Bedrock tip:"
            echo "   Ensure your AWS credentials and AWS_REGION (us-gov-west-1 or us-gov-east-1) are set."
          '';
        };
      });
}
