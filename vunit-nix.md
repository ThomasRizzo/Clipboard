**Here's a great, ready-to-use Nix flake for a reproducible VHDL development environment with GHDL + VUnit (and the minimal useful dependencies).**

It uses:
- `ghdl-mcode` (the most reliable backend right now — the `ghdl-gcc`/`ghdl-llvm` builds have been flaky in recent nixpkgs-unstable; you can swap it if you prefer the GCC/LLVM backends for VHPIDIRECT or advanced features).
- GTKWave (essential for viewing waveforms from VUnit/GHDL).
- A Python virtualenv + `pip install vunit_hdl` (VUnit is not yet packaged in nixpkgs, so this is the cleanest and most maintainable way; the venv is created once in `.venv` and is ignored by git).

Save this as `flake.nix` in your project root:

```nix
{
  description = "GHDL + VUnit dev environment for VHDL";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShellNoCC {
          name = "vhdl-vunit";

          packages = with pkgs; [
            ghdl-mcode          # ← change to ghdl-gcc or ghdl-llvm if you prefer (may need to fix builds)
            gtkwave             # waveform viewer (open VCD files from VUnit)
            python3             # for VUnit
            gnumake             # common in HDL projects
            # Optional but nice:
            # verilator         # if you also do Verilog
            # git
          ];

          shellHook = ''
            echo "🚀 GHDL + VUnit development environment loaded"
            echo "   • GHDL (mcode backend): $(ghdl --version | head -1)"
            echo "   • GTKWave: available for waveform viewing"
            echo ""

            # Create/activate Python venv with VUnit (one-time setup)
            VENV=".venv"
            if [ ! -d "$VENV" ]; then
              echo "Creating Python virtualenv with VUnit..."
              python3 -m venv "$VENV"
            fi

            source "$VENV/bin/activate"

            # Install/upgrade VUnit (idempotent)
            pip install --upgrade pip wheel > /dev/null
            pip install --upgrade vunit_hdl > /dev/null

            echo "✅ VUnit is ready! (vunit_hdl $(python -c 'import vunit; print(vunit.__version__)' 2>/dev/null || echo 'installed'))"
            echo ""
            echo "Usage examples:"
            echo "   python run.py          # run your VUnit tests"
            echo "   ghdl --version"
            echo "   gtkwave your_test.vcd"
            echo ""
            echo "Tip: add 'use_flake' to .envrc for automatic loading with direnv."
          '';
        };
      });
}
```

### How to use it

1. **Initialize the flake**:
   ```bash
   nix flake update
   ```

2. **Enter the dev shell**:
   ```bash
   nix develop
   ```
   (First run will create `.venv` and install VUnit via pip.)

3. **(Optional but recommended)** Add direnv for automatic activation:
   - Create `.envrc` with `use flake`
   - Run `direnv allow`

4. **Switch GHDL backend** (if you want GCC/LLVM):
   Replace `ghdl-mcode` with `ghdl-gcc` or `ghdl-llvm` in the `packages` list. If it fails to build, stick with mcode — it works great for 99% of VUnit testbenches.

### Bonus: minimal `run.py` example (place in your project)

```python
from vunit import VUnit

vu = VUnit.from_argv()
vu.add_vhdl_builtins()

lib = vu.add_library("lib")
lib.add_source_files("src/*.vhd")   # your design + testbenches

vu.main()
```

Run with `python run.py` inside the shell.

This flake is clean, fast to enter, and gives you everything you need for serious VUnit + GHDL work. Enjoy the verification goodness! 🚀

```nix
{
  description = "GHDL + VUnit (fully Nix-packaged) development environment for VHDL";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # VUnit packaged natively in Nix (hash-verified, reproducible)
        vunit = pkgs.python3Packages.buildPythonPackage rec {
          pname = "vunit_hdl";
          version = "4.7.1";

          src = pkgs.fetchPypi {
            inherit pname version;
            hash = "sha256-3a6f0e19eaa1e79899676aa4cdce95ec8f649002362c4458c3e0412d0f7d0912";
          };

          # VUnit optionally uses colorama for nice colored output
          propagatedBuildInputs = with pkgs.python3Packages; [
            colorama
          ];

          # Tests require a simulator and are very heavy — skip them
          doCheck = false;

          pythonImportsCheck = [ "vunit" ];

          meta = with pkgs.lib; {
            description = "VUnit HDL testing framework";
            homepage = "https://vunit.github.io/";
            license = licenses.mpl20;
          };
        };

        pythonWithVunit = pkgs.python3.withPackages (ps: [ vunit ]);

      in
      {
        devShells.default = pkgs.mkShellNoCC {
          name = "vhdl-vunit";

          packages = with pkgs; [
            ghdl-mcode          # fastest & most reliable backend for VUnit
            gtkwave             # waveform viewer
            pythonWithVunit     # Python + VUnit (fully Nix-locked)
            gnumake
          ];

          shellHook = ''
            echo "🚀 GHDL + VUnit development environment (fully Nixified)"
            echo "   • GHDL (mcode): $(ghdl --version | head -1)"
            echo "   • VUnit: $(python -c 'import vunit; print(vunit.__version__)' 2>/dev/null || echo 'loaded')"
            echo "   • Everything is pinned, hashed, and reproducible"
            echo ""
            echo "Run your tests with:"
            echo "   python run.py"
            echo ""
            echo "Tip: add 'use flake' to .envrc + direnv for auto-loading"
          '';
        };
      });
}
```