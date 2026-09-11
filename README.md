# Clipboard

A personal collection of notes, Nix flakes, scripts, and documentation for AI tooling, embedded development, reproducible environments, and various experiments.

## What's Inside

- **Nix development shells** (`flake.nix`) – Quick, reproducible environments with tools like OpenCode, Python, Git, etc.
- Project-specific notes:
  - `DE0-MIGRATION.md` – FPGA board migration guide (DE0 Cyclone III → DE0-Nano Cyclone IV)
  - `codex-cli-windows-sandbox.md`, `opencode-fsharp-subagent.md`, `minimal-agent.md`, etc. – AI/agentic coding workflows
  - `Pi-nix.md`, `vunit-nix.md`, `oc-rust-sandbox.nix` – Nix + hardware/embedded topics
  - `graphify/` – Related Nix flake
  - Brainstorming & other docs (`Brainstorm.md`, `Timeplot.md`, `clap-selfupdate.md`, etc.)
  - `egui-larger-app-best-practices.md` – Structure and architecture notes for larger egui/eframe apps, with links to solid examples
  - `egui-pdf-rig-tesseract-setup.md` – egui + PDF + RIG + OCR stack sketch
  - `grok-build-intranet-govcloud.md` – **start here on the corp intranet**: build Grok Build from GitHub, GovCloud Grok 4.6 only (Bedrock Mantle + AWS token helper, no `x.ai`)

## Quick Start

```bash
# Enter the dev shell (no clone needed)
nix develop github:ThomasRizzo/Clipboard

# Or clone
git clone https://github.com/ThomasRizzo/Clipboard.git
cd Clipboard
nix develop
```

## Updating

```bash
nix flake update
```

Made for quick access to modern dev tools and personal knowledge base. Contributions welcome for improvements!

---

See individual `.md` files for detailed notes on each topic.
