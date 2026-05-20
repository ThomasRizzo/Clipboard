{
  description = "Graphify (pinned + auto-setup) with extras: pdf, office, mcp, svg, bedrock, sql";

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

            # Ensure local venv exists
            if [ ! -d .venv ]; then
              echo "Creating virtual environment..."
              uv venv --seed
            fi

            # Activate venv
            source .venv/bin/activate

            # Install / upgrade to exact pinned version + all extras
            echo "Installing / upgrading graphifyy with extras..."
            uv pip install --upgrade \
              "graphifyy[${extras}]==${graphifyVersion}"

            echo ""
            echo "✅ Graphify is fully set up and ready!"
            echo "Commands:"
            echo "   graphify --help"
            echo "   graphify install          # Register as AI coding skill (recommended)"
            echo ""
            echo "💡 For AWS GovCloud Bedrock:"
            echo "   Make sure AWS credentials are configured and AWS_REGION is set to us-gov-west-1 or us-gov-east-1"
            echo ""
            echo "You are now in a fully activated Python environment with Graphify."
          '';
        };
      });
}
