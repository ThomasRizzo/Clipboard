{
  description = "Graphify with extras: pdf, office, mcp, svg, bedrock, sql";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShells.default = pkgs.mkShellNoCC {
          name = "graphify-with-extras";

          buildInputs = with pkgs; [
            python312
            uv
            # System libraries needed by Graphify extras
            pkg-config
            cairo
            pango
            harfbuzz
            fontconfig
            freetype
            libxml2
            libxslt
            # Additional for PDF/Office/SVG
            poppler
            libreoffice
          ];

          shellHook = ''
            echo "🚀 Graphify Nix environment ready (pdf, office, mcp, svg, bedrock, sql)"
            echo ""
            echo "Install commands:"
            echo "  uv tool install \"graphifyy[pdf,office,mcp,svg,bedrock,sql]\""
            echo "  # or"
            echo "  uv venv && source .venv/bin/activate && uv pip install \"graphifyy[pdf,office,mcp,svg,bedrock,sql]\""
            echo ""
            echo "Then: graphify --help"
            echo "AWS Bedrock/GovCloud: Configure your AWS credentials and set AWS_REGION to a GovCloud region."
          '';
        };
      });
}
