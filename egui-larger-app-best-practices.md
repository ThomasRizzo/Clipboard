# Best Practices for Larger egui Apps

Notes for structuring non-trivial egui / eframe applications so they stay maintainable as features grow (history, search, background work, persistence, multi-panel UIs, etc.).

Immediate-mode is simple for small apps. Larger ones need deliberate separation of concerns, clear ownership of state, and non-blocking work so the UI stays responsive.

## Core Principles

1. **Separate UI from domain logic**  
   Keep pure business / data logic in its own crate(s). The egui layer should mostly read state and emit intents or commands. Avoid stuffing SQLite queries, clipboard polling, or network calls inside `App::update`.

2. **Centralize app state, modularize UI**  
   One root `App` (or `WrapApp`) that owns shared state. Split the UI into focused modules or widgets (panels, dialogs, history list, settings). Prefer small `ui` methods that take `&mut self` or a focused state slice over a single giant `update`.

3. **Keep the frame non-blocking**  
   Long work (search, OCR, file I/O, clipboard monitoring) belongs on background threads or async tasks. Communicate results via channels (`std::sync::mpsc`, `crossbeam`, or `tokio` channels). Drive UI from the latest snapshot; never block the egui frame.

4. **Prefer immutable snapshots during the UI pass**  
   Patterns that work well:
   - Collect events/commands during the UI pass, apply them after.
   - Or keep a mutable model outside the UI and pass an immutable view into widgets (Elm-inspired / pure view).
   Avoid deep mutable borrows that fight the borrow checker across nested panels.

5. **Use workspace crates early**  
   Typical split:
   - `*-core` — domain types, storage, pure logic (no egui)
   - `*-ui` or the binary crate — eframe + egui widgets
   - Optional `*-cli` / `*-server` if you share the core

6. **Persistence and config**  
   Use `eframe` memory / `serde` for UI state (window size, open panels, last filters). Keep durable data (clipboard history, documents) in an explicit store (SQLite, files) with clear ownership.

7. **Viewport and layout discipline**  
   Use `CentralPanel`, `SidePanel`, `TopBottomPanel` consistently. For multi-window apps, prefer deferred viewports when independent repaint matters; immediate viewports when sharing state is simpler. See the official multiple-viewports example.

8. **Testing and demos**  
   Extract demo / showcase UI into a library crate (like `egui_demo_lib`) so you can exercise widgets without the full app. Prefer pure functions for domain logic so unit tests stay easy.

## Recommended Example Projects

These are large enough to show real structure, not just hello-world widgets.

| Project | Why it is useful | Link |
|--------|-------------------|------|
| **egui official demo** | Canonical structure: `egui_demo_lib` (UI + examples) vs thin `egui_demo_app` shell. Best starting point for modular UI organization. | [emilk/egui – demo lib & app](https://github.com/emilk/egui/tree/master/crates/egui_demo_lib) · [ARCHITECTURE.md](https://github.com/emilk/egui/blob/master/ARCHITECTURE.md) |
| **eframe template** | Minimal but correct app skeleton (native + web). Good baseline before you grow structure. | [emilk/eframe_template](https://github.com/emilk/eframe_template) |
| **Ferrite** | Full text editor on egui/eframe: custom editor, split views, persistence, platform concerns. Real-world larger app layout and upgrade notes. | [OlaProeis/Ferrite](https://github.com/OlaProeis/Ferrite) |
| **large-text-viewer** | Explicit three-layer design: presentation (egui) / application / core processing. Background threads + channels, constant memory, clear crate split. | [acejarvis/large-text-viewer](https://github.com/acejarvis/large-text-viewer) (see architecture notes on DeepWiki or repo docs) |
| **realworld-egui-seaorm** | Same UI and domain shared across fat-client, client–server, and WASM variants. Good multi-crate / multi-target example. | [xdobry/realworld-egui-seaorm](https://github.com/xdobry/realworld-egui-seaorm) |
| **egui_mobius** | Modular “citizen” panels, dispatcher, reactive shared state. Useful when you want dockable/reusable panels and clearer message routing. | [saturn77/egui_mobius](https://github.com/saturn77/egui_mobius) |
| **Clean Architecture with Rust (egui desktop)** | Domain-centric workspace with an egui desktop interface among others. Shows dependency direction and shared core. | [flosse/clean-architecture-with-rust](https://github.com/flosse/clean-architecture-with-rust) |
| **ClipVault (egui clipboard managers)** | Practical clipboard-manager shape: tray, history, SQLite, settings. Smaller than the above but closer to a clipboard product. | [remysedlak/clipvault](https://github.com/remysedlak/clipvault) · [AndreiVladescu/ClipVault](https://github.com/AndreiVladescu/ClipVault) |

Also useful:

- Official multiple-viewports example: [egui/examples/multiple_viewports](https://github.com/emilk/egui/tree/master/examples/multiple_viewports)
- egui docs and crate overview: [docs.rs/egui](https://docs.rs/egui) and the ARCHITECTURE.md linked above

## Practical Starter Layout for a Larger App

```text
my-app/
  Cargo.toml                 # workspace
  crates/
    my-app-core/             # domain, storage, pure logic (no egui)
    my-app-ui/               # eframe App, panels, widgets
  # or a single binary that depends on core
```

Inside the UI crate:

- `app.rs` — `eframe::App` impl, top-level layout, channel polling
- `state.rs` / `model.rs` — serializable UI + domain snapshot
- `panels/` — side panel, history list, settings, etc.
- `commands.rs` or message enum — intents produced by UI, applied after the frame or by a background worker

## Clipboard / History App Notes

If the goal is a clipboard history manager (or similar):

- Poll or listen for clipboard changes off the UI thread; push entries into a bounded history store.
- Persist with SQLite (or similar); keep the in-memory list as a view/cache.
- UI: searchable list + detail + tags/filters; settings in a separate panel or window.
- System tray + global hotkey are common; keep tray logic outside the main egui update path where possible.
- See the ClipVault-style repos above for concrete tray + history patterns.

## Related Notes in This Repo

- `egui-pdf-rig-tesseract-setup.md` — egui + PDF + RAG / OCR stack sketch (layered core vs UI).

---

Last updated: 2026-08-13
