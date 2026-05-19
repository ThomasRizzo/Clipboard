{ description = "Nick's flake – dev shell with latest git + Python + OpenCode (GitHub)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Pull the latest OpenCode (AI coding agent) directly from GitHub.
    # flake.lock will automatically pin the exact commit + narHash.
    # Run `nix flake update opencode` anytime to get the absolute newest version.
    opencode.url = "github:anomalyco/opencode";
  };

  outputs = { self, nixpkgs, opencode }:
    let
      # Supported systems
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSystem = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      devShells = forEachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          # Latest OpenCode pulled from its GitHub flake (pinned by hash in flake.lock)
          openCodePkg = opencode.packages.${system}.opencode
                      or opencode.packages.${system}.default
                      or pkgs.opencode;
        in
        pkgs.mkShellNoCC {
          name = "nick-shell";

          packages = with pkgs; [
            git                  # latest git from nixpkgs unstable
            python312Full        # latest Python 3.12 with full stdlib + pip etc.
            openCodePkg          # latest OpenCode straight from GitHub
          ];

          # Optional: nice welcome message when you enter the shell
          shellHook = ''
            echo "🚀 Welcome to Nick's shell!"
            echo "   • git:      $(git --version)"
            echo "   • python:   $(python --version)"
            echo "   • opencode: $(opencode --version 2>/dev/null || echo 'ready')"
            echo ""
            echo "Type 'exit' or Ctrl+D to leave the shell."
          '';
        }
      );

      # Convenience alias so `nix develop` works without specifying a system
      devShells.default = self.devShells.${builtins.currentSystem or "x86_64-linux"}.default or null;
    };
}