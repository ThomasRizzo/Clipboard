# egui + pdf-reader-core + RIG + Bundled Tesseract Setup Notes

Notes for building a local-first RAG agent / PDF tool using:

- **egui** for the UI
- **pdf-reader-core** (from SylphxAI/pdf-reader-mcp) for structured PDF extraction (text layer + Markdown + tables + geometry)
- **RIG** (0xPlaygrounds/rig) for the agent / tool-calling / RAG orchestration layer
- A **bundled Rust Tesseract** crate for OCR on scanned pages (no system Tesseract required)

## Goal

A self-contained desktop app (or library + egui front-end) that can:

1. Open PDFs
2. Prefer native text extraction when available
3. Fall back to OCR (via bundled Tesseract) for scanned / sparse pages
4. Produce clean Markdown + structured chunks for a RIG agent
5. Expose tools the agent can call (read page, search, OCR region, etc.)

## Crates Overview

### 1. egui

Immediate-mode GUI. Use `eframe` for the application shell.

```toml
[dependencies]
eframe = { version = "0.29", default-features = false, features = ["default_fonts", "glow"] }
egui = "0.29"
```

### 2. pdf-reader-core

This is the pure-Rust core from the SylphxAI project (not published on crates.io as of 2026-07).

Recommended dependency (git):

```toml
pdf-reader-core = { git = "https://github.com/SylphxAI/pdf-reader-mcp", package = "pdf-reader-core" }
```

Or vendor the `crates/pdf-reader-core` directory into your workspace.

Key capabilities you want from the core:

- Native text layer extraction (selectable text)
- Layout-aware Markdown conversion
- Table detection / cell geometry
- Page rendering to image (for OCR path)
- Provenance / bounding boxes

The TypeScript MCP launcher is **not** needed. Call the Rust APIs directly.

### 3. RIG (agent framework)

https://github.com/0xPlaygrounds/rig

```toml
rig-core = "0.x"          # check current version
# + whatever provider adapters you need (OpenAI, Anthropic, local, etc.)
```

RIG gives you:

- Tool definitions the LLM can call
- Agent loops
- Easy integration of your PDF tools as `Tool` implementations

### 4. Bundled Tesseract (no system install)

Options (pick one):

**A. Preferred for fully offline / no system deps:**

- `kreuzberg-tesseract` (static / bundled build of Tesseract + Leptonica)
- or pure-Rust alternatives such as `ocrs` if you want to avoid C++ entirely

**B. Classic (requires system Tesseract):**

- `tesseract` crate + system libraries

For a self-contained binary, go with the bundled approach.

Example (kreuzberg style):

```toml
kreuzberg-tesseract = "0.x"   # check crates.io for latest
```

You will still need the traineddata files (eng.traineddata etc.). Bundle them in your binary or ship them next to the executable.

## High-level Architecture

```
┌──────────────────────────────────────────────┐
│                  egui / eframe               │
│  (file picker, page viewer, chat, tools UI)  │
└────────────────────┬─────────────────────────┘
                     │
┌────────────────────▼─────────────────────────┐
│                  RIG Agent                   │
│  - tools: read_pdf, search, ocr_page, ...    │
│  - RAG over extracted Markdown / chunks      │
└────────────────────┬─────────────────────────┘
                     │
┌────────────────────▼─────────────────────────┐
│            pdf-reader-core                   │
│  - open document                             │
│  - extract text layer / Markdown             │
│  - detect sparse / scanned pages             │
│  - render page → image                       │
└────────────────────┬─────────────────────────┘
                     │ (when needed)
┌────────────────────▼─────────────────────────┐
│         Bundled Tesseract (or ocrs)          │
│  - OCR image → text + boxes + confidence     │
└──────────────────────────────────────────────┘
```

## Suggested Implementation Steps

1. **Workspace setup**
   - Create a Cargo workspace
   - Add `pdf-reader-core` as a git/path dependency
   - Add `eframe` + `egui`
   - Add `rig-core`
   - Add your chosen Tesseract / OCR crate

2. **Minimal PDF loader**
   - Use `pdf-reader-core` to open a PDF and get:
     - page count
     - native text layer (if present)
     - Markdown representation

3. **OCR path**
   - Detect pages with little/no selectable text
   - Render those pages to PNG/RGB via the core
   - Feed the image into the bundled Tesseract crate
   - Merge OCR text + word boxes back into your document model

4. **RIG tools**
   - Implement a few tools, e.g.:
     - `read_page(page: u32)`
     - `search(query: &str)`
     - `ocr_page(page: u32)`
     - `get_tables(page: u32)`
   - Register them with a RIG agent

5. **egui front-end**
   - Simple layout: left = PDF list / page thumbnails, center = content or chat, right = tool results / citations
   - Show provenance (page + bbox) when the agent answers

6. **Offline concerns**
   - Bundle `eng.traineddata` (and any other languages)
   - Prefer pure-Rust or statically-linked OCR so the binary has zero system dependencies
   - Keep model weights (if any) next to the binary or inside a Nix store path

## Useful References

- SylphxAI pdf-reader-mcp: https://github.com/SylphxAI/pdf-reader-mcp  
  (look under `crates/pdf-reader-core`)
- RIG: https://github.com/0xPlaygrounds/rig
- egui / eframe: https://github.com/emilk/egui
- Tesseract traineddata: https://github.com/tesseract-ocr/tessdata (or tessdata_fast)

## Open Questions / TODOs

- Exact public API surface of `pdf-reader-core` (may need to vendor and stabilize a thin wrapper)
- Best bundled Tesseract crate that is actively maintained and compiles cleanly on Windows/macOS/Linux
- Whether to also support pure-Rust OCR (`ocrs`) as a second backend for even fewer native deps
- How to expose page renders efficiently to egui (texture upload)

---

Last updated: 2026-07-31
