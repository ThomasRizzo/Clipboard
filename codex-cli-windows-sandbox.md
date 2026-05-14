**When you set up the "elevated sandbox" for OpenAI Codex CLI on Windows (the preferred native mode), it performs a one-time elevated (admin) setup to create a secure, OS-level isolation environment for the AI agent’s commands.**

This is **not** a separate standalone installer. It happens automatically (or when you choose it) the first time you run the Codex CLI natively in PowerShell after installing via `npm install -g @openai/codex` (or similar). Codex prompts you during onboarding and runs a dedicated elevated binary (`codex-windows-sandbox-setup.exe`) that requires a UAC/admin approval.

### Exactly What the Elevated Sandbox Setup Does
It modifies your Windows system (once, persistently) to enable strong isolation while still allowing the agent to work productively inside your workspace. Here’s the precise list of actions:

- **Creates two dedicated low-privilege local user accounts** (they persist on your machine):
  - `CodexSandboxOffline` — for commands that should have **no network access**.
  - `CodexSandboxOnline` — for commands that are allowed network access.

- **Stores the sandbox users’ credentials securely** using Windows Data Protection API (DPAPI) in a location the sandbox users themselves cannot access.

- **Creates or updates Windows Firewall rules** to **block all outbound network traffic** specifically for the `CodexSandboxOffline` user (this is a strong, user-level enforcement that applies to all child processes).

- **Grants read/execute permissions (ACLs)** to the sandbox users on key system locations so the agent can still read necessary files (e.g., your user profile, `C:\Windows\`, `C:\Program Files\`, `C:\Program Files (x86)\`, `C:\ProgramData\`, etc.). This is done asynchronously.

- **Sets up filesystem write boundaries** for your workspaces:
  - Grants write/execute/delete access (via a synthetic SID called `sandbox-write`) to your current working directory and any additional `writable_roots` you configure.
  - Explicitly **denies** write access to sensitive folders like `.git`, `.codex`, and `.agents` inside those roots (for safety).

- **Configures the command execution flow**:
  - Codex uses a `codex-command-runner.exe` binary that runs as one of the sandbox users.
  - It creates a **restricted token** (using `CreateRestrictedToken`) that includes only `Everyone`, the logon SID, and the `sandbox-write` SID.
  - Child processes (git, npm, builds, tests, etc.) are launched via `CreateProcessAsUserW` under this restricted token.
  - Writes are only allowed where the ACLs + restricted token permit them → the agent is confined to your approved workspace.

- **Runs commands in a private desktop** (for UI/process isolation) unless you disable it with `windows.sandbox_private_desktop = false`.

### Key Differences from the “Unelevated” Sandbox
- **Elevated** (recommended): Requires admin **only at setup**. Stronger network isolation (real firewall rules), dedicated users, better overall security and performance.
- **Unelevated** (fallback): No admin required, weaker network controls, runs under your real user account with just restricted tokens + ACLs.

### Configuration
After setup, you control it in `~/.codex/config.toml` (or the equivalent Codex config location):
```toml
[windows]
sandbox = "elevated"   # or "unelevated" as fallback
```

You can also combine it with sandbox modes like `workspace-write` (default) and approval policies (`--ask-for-approval on-request`, etc.).

### Why It Needs Elevation (and What It Doesn’t Do)
Elevation is needed **only once** to create users, firewall rules, and system ACLs. After that, `codex.exe` itself runs **unelevated**—the agent never gets admin rights. It does **not** give the AI full system access; it actually restricts it more tightly than running without a sandbox.

In short: the elevated sandbox turns your Windows machine into a safer environment where Codex can autonomously run commands (edit files, run builds, etc.) **only inside the directories you trust**, with strong network and privilege boundaries enforced by Windows itself. This is the mechanism OpenAI built specifically to make the native Windows experience both powerful and safe.

If you run into issues (e.g., enterprise policies blocking it), Codex falls back to the unelevated sandbox or you can use WSL2 instead. Check the logs in `CODEX_HOME/.sandbox/sandbox.log` for details.