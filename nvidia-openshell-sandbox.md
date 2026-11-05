# NVIDIA OpenShell — sandbox reference

> Exact name: **NVIDIA OpenShell** (repo `NVIDIA/OpenShell`). Latest stable: **v0.1.7**, released 2026-11-03 (GitHub Releases, checked 2026-11-04). Facts below come from the repo README and `docs/` on `main` (same content as docs.nvidia.com/openshell). OpenShell ships weekly, so details change fast.

## What it is
"The safe, private runtime for autonomous AI agents." Agents (Claude Code, OpenCode, Codex, or any agent in an OCI image) run inside **sandboxes**, and a **policy** declares what each one may touch. OpenShell enforces that policy and gives agents scoped credentials without exposing the real secrets.

Architecture: **gateway** (control plane: sandboxes, policy, access) → **supervisor** (outside the workload; holds the credentials and opens upstream connections) → **sandbox** (`openshell-sandbox` runtime binary inside the boundary; owns the agent process tree).

## Security and isolation model
- **Kernel-level enforcement:** **Landlock** LSM restricts filesystem paths. **seccomp** (user notification) intercepts TCP opens and DNS queries and hands them to the supervisor's policy proxy. Every outbound connection is **denied unless a policy rule allows it**.
- **Credentials:** agents never see real credentials. The supervisor injects them only into requests bound for approved endpoints (via "providers").
- **Formally verified policy changes:** the policy **prover** and **advisor** flag risky new access, such as a new host with credentials or a new API method, so a human reviews it first.
- A sandbox must pass Landlock and seccomp qualification. The policy's `landlock` section controls whether the sandbox still starts when the filesystem rules can't be applied.
- Kubernetes: the CNI **must enforce `NetworkPolicy`**, or sandbox pods can bypass OpenShell's network policy.

## Supported platforms (Support Matrix)
| Platform | Arch | Status |
|---|---|---|
| Linux (Debian/Ubuntu) | x86_64, aarch64 | Supported |
| macOS (Docker Desktop) | Apple Silicon arm64 | Supported |
| Windows (WSL 2 + Docker Desktop) | x86_64 | Experimental |
| Native Windows (MXC) | x86_64, ARM64 | `windows` branch only, dev, not production-qualified |

- The CLI on Linux is a static musl binary (no glibc needed). The standalone `openshell-gateway` binary needs glibc ≥ 2.28 (Ubuntu 20.04+, RHEL/Rocky 8+, AL2023, Fedora 32+).
- Gateway images: `linux/amd64` and `linux/arm64`.
- **Runtimes / compute drivers:** Docker (Engine or Desktop ≥ 28.0), Podman 5.x (Linux, cgroups v2, rootless user socket), Kubernetes ≥ 1.29 + Helm 3 (needs the kubernetes-sigs Agent Sandbox controller), MicroVM (libkrun, using KVM on Linux or Hypervisor.framework on macOS).
- **GPU:** `openshell sandbox create --gpu [N]`. Docker and Podman use **NVIDIA CDI** devices (configure Docker CDI *before* starting the gateway, or restart the gateway afterwards). Kubernetes sets the `nvidia.com/gpu` limit. VM gateways allow only 1 GPU. ⚠️ The docs I checked list **no minimum NVIDIA driver or Container Toolkit version**: unconfirmed.
- Default workload image: `nvcr.io/nvidia/base/ubuntu:24.04` (minimal, no agent CLIs).

## Install and getting started
```bash
# Linux/macOS: installs the CLI, policy prover and a local gateway, then starts the gateway
curl -LsSf https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh | sh
# Pin a release: set OPENSHELL_VERSION=<tag> for the installer
openshell status                         # confirm the CLI can reach the gateway
openshell sandbox create --name demo     # minimal Ubuntu sandbox, login shell
openshell sandbox create -- claude       # or -- opencode / -- codex; prompts to create a provider from env keys
openshell sandbox create --name my-agent \
  --from ghcr.io/anomalyco/opencode:latest --provider openrouter \
  -- opencode -m openrouter/nvidia/nemotron-3.5-lightning:free
openshell --help
```
- On Linux packages, the local gateway runs as a systemd user service at `https://127.0.0.1:17670`. Config is in `~/.config/openshell/gateway.toml`, with env overrides in `gateway.env`. Set `compute_driver` to pin a runtime (it is auto-detected otherwise).
- Packages: Debian, RPM, Homebrew, snap. Kubernetes: Helm chart `deploy/helm/openshell`.
- Other flags: `--detach`, `--cpu`, `--memory`, `--policy`, `--driver-config-json` (experimental).

## Key concepts
Gateway · Sandbox (main process after `--`; on exit it is `Completed` for code 0 or `Error`/`MainProcessFailed` otherwise) · Provider / provider profiles (credentials, endpoints, allowed executables) · Policy · Workspaces · Compute drivers · Extensibility (supervisor middleware, gateway interceptors, isolation backends) · SDKs (Python, Go, Rust, TypeScript).

## Policy controls (YAML, `version: 1`)
| Section | Controls | Enforced by | When |
|---|---|---|---|
| `filesystem_policy` | read / read-write paths | Landlock | startup |
| `landlock` | fail vs. start without FS rules | runtime | startup |
| `process` | run-as user/group | Docker/Podman | creation |
| `network_policies` | per-binary destinations + allowed requests (e.g. read-only API, MCP methods) | network proxy | live, hot-reloadable |
| `network_middlewares` | extra inspection/transform/block | network proxy | live |

Policy precedence: global (admin) policy → the sandbox's saved policy (`--policy` takes priority over `OPENSHELL_SANDBOX_POLICY`) → policy in the image → restrictive default. Provider rules merge into the "effective policy". An invalid image policy blocks startup.

## Limitations and known issues (from the docs)
- WSL 2 is experimental. Native Windows (MXC) is a dev branch only.
- VM mounts: at most 32 on an arm64 host and 3 on an x86_64 host. VM mounts need libkrun, so GPU sandboxes can't use them. libkrun does not confine a compromised guest kernel to the mount source.
- MCP tool-argument matching is not supported in network rules. Codex WebSocket transport is experimental/unsupported.
- IPv6 edge-login callbacks fail in Chrome (a CSP limitation in the browser).
- Interfaces marked Experimental may change in patch releases. Security fixes cover only the latest minor release and the one before it (N-1).
- OTLP: no HTTP/JSON and no zstd.

## License
Apache-2.0 (© NVIDIA CORPORATION & AFFILIATES).

## Sources
- Repo: https://github.com/NVIDIA/OpenShell
- Releases: https://github.com/NVIDIA/OpenShell/releases
- Docs: https://docs.nvidia.com/openshell (e.g. /how-it-works/sandboxes/overview)
- Support matrix: https://github.com/NVIDIA/OpenShell/blob/main/docs/about/support-matrix.mdx
- Installation: https://github.com/NVIDIA/OpenShell/blob/main/docs/about/installation.mdx
- Policies: https://github.com/NVIDIA/OpenShell/blob/main/docs/how-it-works/policies/overview.mdx
