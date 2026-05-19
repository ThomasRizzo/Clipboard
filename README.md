# Nick's Dev Shell

A clean, reproducible Nix development shell containing:

- **git** (latest from nixpkgs unstable)
- **Python 3.12** (full distribution)
- **OpenCode** — latest version pulled directly from [GitHub](https://github.com/anomalyco/opencode)

## How to use

### One-liner (no cloning needed)
```bash
nix develop github:ThomasRizzo/Clipboard
```

### Or clone the repo
```bash
git clone https://github.com/ThomasRizzo/Clipboard.git
cd Clipboard
nix develop
```

## Updating

To pull the newest OpenCode (or any other updates):
```bash
nix flake update opencode
```

Then re-enter the shell with `nix develop`.

---

Made with ❤️ for quick access to modern dev tools.
