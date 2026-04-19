```nix
{
  description = "Dev shell with Pi AI coding agent + subagent extension (AWS Bedrock GovCloud Sonnet 4.5)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Bash wrapper that starts Pi pre-configured for AWS Bedrock GovCloud (Claude Sonnet 4.5)
        startPiScript = pkgs.writeShellScriptBin "start-pi" ''
          #!/usr/bin/env bash
          set -euo pipefail

          echo "🚀 Pi AI Agent Launcher (AWS Bedrock GovCloud – Claude Sonnet 4.5)"

          # Check for required AWS GovCloud credentials (exactly as requested – from environment only)
          if [[ -z "''${AWS_ACCESS_KEY_ID:-}" || -z "''${AWS_SECRET_ACCESS_KEY:-}" || -z "''${AWS_REGION:-}" ]]; then
            echo "❌ Error: AWS credentials not found in environment variables."
            echo ""
            echo "Please export your GovCloud IAM keys before running start-pi:"
            echo "  export AWS_ACCESS_KEY_ID=AKIA..."
            echo "  export AWS_SECRET_ACCESS_KEY=..."
            echo "  export AWS_REGION=us-gov-west-1        # (or us-gov-east-1)"
            echo ""
            echo "Then run this script again."
            exit 1
          fi

          echo "✅ AWS credentials detected (GovCloud)"
          echo "📍 Region: $AWS_REGION"
          echo "🧠 Model : us.anthropic.claude-sonnet-4-5-20250929-v1:0"
          echo "🔌 Provider: amazon-bedrock"
          echo ""

          # Forward any extra arguments (e.g. --verbose, custom flags) to Pi
          exec pi --provider amazon-bedrock \
                   --model us.anthropic.claude-sonnet-4-5-20250929-v1:0 \
                   "$@"
        '';
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            nodejs_22
            ripgrep
            fd
            git
            awscli2
            # Canvas / image dependencies (for any Pi extensions)
            cairo pango libjpeg giflib librsvg pixman pkg-config python3
            # Our custom launcher script
            startPiScript
          ];

          shellHook = ''
            echo "🚀 Setting up Pi coding agent dev shell..."

            # Keep NPM packages isolated
            export NPM_CONFIG_PREFIX="$PWD/.pi-npm"
            mkdir -p "$NPM_CONFIG_PREFIX/bin"
            export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"

            # Install Pi if not present
            if ! command -v pi >/dev/null 2>&1; then
              echo "📦 Installing @mariozechner/pi-coding-agent..."
              npm install -g @mariozechner/pi-coding-agent
            else
              echo "✅ Pi already available"
            fi

            # Install subagent extension (change package if you prefer another)
            echo "🔌 Installing subagent extension (nicobailon/pi-subagents)..."
            pi install npm:nicobailon/pi-subagents || true

            echo ""
            echo "✅ Dev shell ready!"
            echo ""
            echo "=== How to start Pi with AWS Bedrock GovCloud Sonnet 4.5 ==="
            echo "Just run:"
            echo "   start-pi"
            echo ""
            echo "Or with extra flags:"
            echo "   start-pi --verbose"
            echo ""
            echo "The wrapper automatically:"
            echo "• Checks your AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_REGION"
            echo "• Uses the exact GovCloud-compatible model ID"
            echo "• Passes any extra arguments to Pi"
            echo ""
            echo "📝 Tip: Add your AWS exports to a .envrc (direnv) or shell profile."
            echo "Happy agentic coding with subagents! 🐧"
          '';
        };
      });
}
```

### What changed / new features
- Added a **fully functional bash wrapper** called `start-pi` (created with `writeShellScriptBin` so it appears as a normal executable in your `$PATH` inside the shell).
- The script **validates** that your AWS GovCloud credentials are present in the environment (exactly as you requested – no hard-coded secrets).
- It launches `pi` with the precise flags:
  ```bash
  pi --provider amazon-bedrock --model us.anthropic.claude-sonnet-4-5-20250929-v1:0
  ```
- Any extra arguments you pass to `start-pi` are forwarded to Pi.
- Updated shellHook to clearly tell you to use the new `start-pi` command.

### How to use
1. Replace your `flake.nix` with the version above.
2. Run:
   ```bash
   nix develop
   ```
3. Inside the shell, simply type:
   ```bash
   start-pi
   ```

That’s it — Pi will start immediately pointed at your GovCloud Claude Sonnet 4.5 instance. Subagents and all other tools remain exactly as before. Enjoy!
