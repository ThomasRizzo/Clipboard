{
  description = "Sandboxed OpenCode CLI (latest upstream + Rust + AWS Bedrock + crates.io only)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    fenix.url = "github:nix-community/fenix";
    fenix.inputs.nixpkgs.follows = "nixpkgs";
    agent-sandbox-nix.url = "github:archie-judd/agent-sandbox.nix";
    opencode.url = "github:anomalyco/opencode";   # ← official flake, always latest
  };

  outputs = { self, nixpkgs, fenix, agent-sandbox-nix, opencode }:
    let
      system = "x86_64-linux";  # or aarch64-linux
      pkgs = import nixpkgs { inherit system; };

      rustToolchain = fenix.packages.${system}.stable.toolchain;

      # Use the latest opencode from upstream flake
      opencodePkg = opencode.packages.\( {system}.default or opencode.packages. \){system}.opencode;

      sandbox = agent-sandbox-nix.lib.mkSandbox {
        pkg = opencodePkg;
        binName = "opencode";           # the binary name inside the package
        outName = "opencode-sandboxed";

        allowedPackages = [
          rustToolchain
          pkgs.git
          pkgs.curl
        ];

        restrictNetwork = true;

        allowedDomains = {
          # AWS Bedrock (add your region(s))
          "bedrock-runtime.us-east-1.amazonaws.com" = "*";
          "bedrock.us-east-1.amazonaws.com" = "*";
          # "crates.io" and static.crates.io for Rust
          "crates.io" = "*";
          "static.crates.io" = "*";
        };

        extraEnv = {
          AWS_ACCESS_KEY_ID = "";
          AWS_SECRET_ACCESS_KEY = "";
          AWS_SESSION_TOKEN = "";
          AWS_REGION = "us-east-1";
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
          echo "✅ Sandboxed opencode (v1.14.41 — latest) ready!"
          echo "Network limited to Bedrock + crates.io only."
          echo "Git pull/push still handled outside the sandbox in CI."
        '';
      };
    };
}