{
  description = "Sandboxed OpenCode — source-code repo fully editable + git commit allowed";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    fenix.url = "github:nix-community/fenix";
    fenix.inputs.nixpkgs.follows = "nixpkgs";
    opencode.url = "github:anomalyco/opencode";
    agent-sandbox-nix.url = "github:archie-judd/agent-sandbox.nix";
  };

  outputs = { self, nixpkgs, fenix, opencode, agent-sandbox-nix }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      rustToolchain = fenix.packages.${system}.stable.toolchain;
      opencodePkg = opencode.packages.\( {system}.default or opencode.packages. \){system}.opencode;

      sandbox = agent-sandbox-nix.lib.mkSandbox {
        pkg = opencodePkg;
        binName = "opencode";
        outName = "opencode-sandboxed";

        allowedPackages = [
          rustToolchain
          pkgs.git
          pkgs.curl
        ];

        restrictNetwork = true;
        allowedDomains = {
          "bedrock-runtime.us-east-1.amazonaws.com" = "*";
          "bedrock.us-east-1.amazonaws.com" = "*";
          "crates.io" = "*";
          "static.crates.io" = "*";
        };

        extraEnv = {
          AWS_ACCESS_KEY_ID = "";
          AWS_SECRET_ACCESS_KEY = "";
          AWS_SESSION_TOKEN = "";
          AWS_REGION = "us-east-1";

          # Git identity for commits inside the sandbox
          GIT_AUTHOR_NAME = "OpenCode Agent";
          GIT_AUTHOR_EMAIL = "opencode@yourcompany.com";
          GIT_COMMITTER_NAME = "OpenCode Agent";
          GIT_COMMITTER_EMAIL = "opencode@yourcompany.com";
        };
      };
    in {
      apps.${system}.default = {
        type = "app";
        program = "${sandbox}/bin/opencode-sandboxed";
      };

      packages.${system}.default = sandbox;

      devShells.${system}.default = pkgs.mkShell {
        packages = [ sandbox ];
        shellHook = ''
          echo "✅ Sandboxed opencode ready"
          echo "• Run from inside source-code/ directory"
          echo "• opencode can run git add / git commit freely"
          echo "• nix-config repo is completely protected"
        '';
      };
    };
}