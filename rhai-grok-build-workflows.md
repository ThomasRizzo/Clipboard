# RHAI and Grok Build Workflows

Notes on the Rhai embedded scripting language and how Grok Build uses it for multi-agent workflows. Written 2026-10-22.

## What is RHAI?

[Rhai](https://github.com/rhaiscript/rhai) is an embedded scripting language and evaluation engine written in Rust. It provides a safe, lightweight way to add scripting to Rust applications.

Key characteristics:

- Syntax is a mix of Rust and JavaScript with dynamic typing.
- Compiles to an AST that can be evaluated repeatedly; optional Grain bytecode VM for higher performance.
- Tight integration with Rust: register native functions, types, methods, getters/setters, and pass any clonable Rust value via `Scope`.
- Sandboxed and protected against common attacks (stack overflows, oversized data, runaway scripts). Any panic is treated as a bug.
- Supports minimal builds by feature flags (disable loops, modules, functions, floats, etc.).
- **no_std support** (requires nightly currently) and WASM builds — relevant for embedded and constrained environments.
- Dual-licensed Apache-2.0 / MIT.

### Official resources

- GitHub: https://github.com/rhaiscript/rhai
- The Rhai Book: https://rhai.rs/book
- Playground: https://rhai.rs/playground
- crates.io: https://crates.io/crates/rhai
- no_std docs: https://rhai.rs/book/start/builds/no-std.html

Minimum Rust version is currently 1.66.0. Few dependencies (smallvec, thin-vec, num-traits, ahash, etc.).

## Grok Build Workflows

Grok Build (xAI’s terminal coding agent) uses Rhai scripts (`.rhai` files) as the orchestration layer for multi-agent workflows.

A workflow is **not** a chat to-do list. It is a Rhai script that:

- Names phases of work
- Controls how many child agents each phase may spawn
- Defines how results roll up
- Journals every agent call so pause/resume does not redo finished work

The mental model: the model is the worker; the `.rhai` file is the foreman.

### Locations

- Project-level: `.grok/workflows/<name>.rhai` (committed with the repo)
- User-level: `~/.grok/workflows/<name>.rhai` (or `$GROK_HOME/workflows/`)

Create one with `/create-workflow <description>`. Grok asks about fan-out, verification, and scope, then authors, smoke-checks, and saves the file.

### Host API (exposed to scripts)

Typical functions available inside a workflow script:

- `agent(prompt, options)` — spawn a single child agent
- `parallel(jobs)` — fan out multiple agents in parallel
- `phase("Name")` — mark a phase boundary (visible in the dashboard)
- `complete(result)` — signal successful completion
- `log(...)`, `await_user`, `output_schema`, `capability_mode` (`read-only`, `read-write`, `execute`, `all`, etc.)

Default agent budget is 128 child-agent calls per run (can be raised up to 1,024). Every `agent()` and every item inside `parallel()` consumes one slot.

### Control

```
/workflow <name> [json-args]
/workflow pause|resume|stop <run-name>
/workflows          # live dashboard
/<unique-name>      # shortcut launch
```

Built-in example: `/deep-research <query>`.

### Sample .rhai shape

```rhai
let meta = #{
    name: "stale-docs",
    description: "Find README claims that no longer match the code",
    when_to_use: "When documentation may have drifted",
    phases: [
        #{ title: "Scout",  detail: "collect candidate claims" },
        #{ title: "Verify", detail: "check each claim" },
        #{ title: "Report", detail: "ranked list of stale claims" },
    ],
};

phase("Scout");
let scout = agent(
    "Read README.md and docs/. List every factual claim about APIs or behavior.",
    #{ label: "scout", capability_mode: "read-only" }
);

phase("Verify");
let jobs = [];
for claim in scout.output.claims {
    jobs.push(#{
        prompt: "Does this claim still match the live code? Claim: " + claim,
        label: "check",
        capability_mode: "read-only"
    });
}
let checks = parallel(jobs);

phase("Report");
let report = agent(
    "Turn these verification notes into one short report of stale claims, strongest first: " + checks.to_json(),
    #{ label: "report" }
);
complete(report.output);
```

(Adapted from public examples; see links below.)

## Big-bucket sample repos

These contain real `.rhai` workflow samples (and sometimes ports to other agents):

| Repo | What it has | Link |
|------|-------------|------|
| Stelliro/grok-build-workflows | Production multi-agent workflows (preflight, search-and-destroy, him-to-implement, implement-from-plan, multi-track-ship, export-workflows) + universal IR and ports for Claude/Codex/Cursor/generic | https://github.com/Stelliro/grok-build-workflows |
| KingInYellows/grok-workflows | Personal library of many Grok Build workflows (branch-review, class-audit, dependabot-pr-triage, docs-refresh, goal-execute, graphite-*, him-to-implement, etc.) + sync scripts | https://github.com/KingInYellows/grok-workflows |
| Bromezz/Rhaiteous | JSON + Markdown → Rhai compiler so you can author workflows without writing Rhai directly | https://github.com/Bromezz/Rhaiteous |
| MrBeldum/star-loop | Autonomous coding loop (one fresh agent per iteration, independent verifier that re-runs gates). Pure Rhai, zero deps | https://github.com/MrBeldum/star-loop |
| xai-org/grok-build | Official source; includes the built-in `deep_research.rhai` | https://github.com/xai-org/grok-build/tree/main/crates/codegen/xai-grok-shell/src/session/workflows |

### Additional reading

- METAGROK how-to: https://metagrok.io/how-to/create-and-run-a-workflow-in-grok-build
- “Grok Build Workflows: What a .rhai File Actually Does” (Medium): https://medium.com/@lcf2212.dev/grok-build-workflows-what-a-rhai-file-actually-does-22382923b10b
- Grok Build CLI cheatsheet (includes workflow commands): https://www.scriptbyai.com/grok-build-cheat-sheet/
- Official Grok Build repo: https://github.com/xai-org/grok-build

## Why it matters for embedded / Rust work

Because Rhai itself supports `no_std`, the same language used for Grok Build orchestration can theoretically be used inside constrained firmware or host tools that already embed Rhai. The host registration model (fine-grained control over what scripts can call) is also a good pattern for any embedded scripting surface.

---

Sources pulled from public GitHub repos, METAGROK, Medium, and the Rhai book as of 2026-10-22.
