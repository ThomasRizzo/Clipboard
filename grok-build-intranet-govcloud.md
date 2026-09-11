# Intranet Grok Build on AWS GovCloud

How to **build and run** [xai-org/grok-build](https://github.com/xai-org/grok-build) on the company intranet the way we run OpenCode: GovCloud Grok 4.6 only, no SpaceXAI hosts.

Do **not** `curl https://x.ai/cli/install.sh` and do **not** run `grok login`. Write config first, then launch.

---

## Get started (copy-paste)

Do these in order on a corp laptop that already runs OpenCode against Bedrock.

### 0. Confirm you can reach what we need

| Need | Hosts | Why |
| --- | --- | --- |
| Clone + git crates | `github.com` | source, `async-openai` fork, `nucleo`, protobuf zip |
| Rust build | `crates.io`, `static.rust-lang.org`, `index.crates.io` | rustup 1.94.0 + cargo |
| Inference | GovCloud Bedrock Mantle (or Runtime) | Grok 4.6 |
| Token mint | STS / IAM in that GovCloud region | same AWS keys as OpenCode |
| Optional TLS intercept | your corp CA file | `GROK_EXTRA_CA_BUNDLE` |
| **Blocked on purpose** | `x.ai`, `api.x.ai`, `auth.x.ai`, Mixpanel | never used |

PyPI (`pypi.org`) is **not** assumed. Prefer cloning the token-generator from GitHub.

Set these once. Change region/host if your account uses West or Runtime instead of Mantle East.

```bash
export AWS_REGION=us-gov-east-1          # or us-gov-west-1
export AWS_PROFILE=govcloud              # whatever OpenCode uses; omit if using env keys
export GROK_BEDROCK_MODEL=xai.grok-4.6
# Mantle (preferred). If this DNS fails, use the Runtime fallback below.
export GROK_BEDROCK_BASE_URL="https://bedrock-mantle.${AWS_REGION}.api.aws/openai/v1"
# Runtime fallback (cross-region id):
# export GROK_BEDROCK_BASE_URL="https://bedrock-runtime.${AWS_REGION}.amazonaws.com/openai/v1"
# export GROK_BEDROCK_MODEL=us.xai.grok-4.6

# If a corp proxy MITMs TLS:
# export GROK_EXTRA_CA_BUNDLE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
```

Sanity:

```bash
aws sts get-caller-identity
# Entitlement (Runtime catalog). Mantle may not list the same way.
aws bedrock list-foundation-models --region "$AWS_REGION" --query "modelSummaries[?contains(modelId, \`grok-4.6\`)]"
```

If Mantle DNS NXDOMAINs, try `bedrock-mantle.${AWS_REGION}.amazonaws-us-gov.com` or switch to the Runtime `base_url` + `us.xai.grok-4.6`.

### 1. Token helper (stdout = JSON only)

Grok Build has no AWS SDK. OpenCode signs with SigV4. This helper turns the same AWS keys into a Bedrock bearer. Grok re-runs it before expiry and on 401.

```bash
mkdir -p ~/bin ~/.grok
git clone https://github.com/aws/aws-bedrock-token-generator-python.git /tmp/aws-bedrock-token-generator-python
python3 -m venv ~/.grok/bedrock-token-venv
~/.grok/bedrock-token-venv/bin/pip install /tmp/aws-bedrock-token-generator-python
# If PyPI is actually allowed you can instead:
# ~/.grok/bedrock-token-venv/bin/pip install aws-bedrock-token-generator
```

```bash
cat > ~/bin/grok-bedrock-token << 'EOF'
#!/usr/bin/env python3
"""Mint a Bedrock bearer for Grok Build. stdout = JSON token payload. stderr = errors."""
from __future__ import annotations

import json
import os
import sys
from datetime import timedelta

# Headless refresh: grok sets GROK_AUTH_EXPIRED=1. Never prompt; never print extra stdout.
from aws_bedrock_token_generator import provide_token

REGION = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION") or "us-gov-east-1"
# 1h is under the 12h max and matches grok's refresh skew (~5 min).
EXPIRES_IN = 3600

def main() -> int:
    try:
        token = provide_token(region=REGION, expiry=timedelta(seconds=EXPIRES_IN))
    except Exception as exc:
        print(f"grok-bedrock-token: {exc}", file=sys.stderr)
        return 1
    if not token:
        print("grok-bedrock-token: empty token", file=sys.stderr)
        return 1
    # JSON so grok gets expires_in. Do not print anything else to stdout.
    sys.stdout.write(json.dumps({"access_token": token, "expires_in": EXPIRES_IN}))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
EOF
chmod +x ~/bin/grok-bedrock-token
# Make sure the venv's python is used:
sed -i "1c\\#!$HOME/.grok/bedrock-token-venv/bin/python3" ~/bin/grok-bedrock-token
```

Test (must print one JSON object, no traceback):

```bash
export PATH="$HOME/bin:$PATH"
~/bin/grok-bedrock-token
# then:
TOKEN=$(~/bin/grok-bedrock-token | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
curl -sS -o /tmp/bedrock-models.json -w "%{http_code}\n" \
  -H "Authorization: Bearer $TOKEN" \
  "$GROK_BEDROCK_BASE_URL/models"
# expect 200. Then a tiny completions/responses call:
curl -sS -X POST "$GROK_BEDROCK_BASE_URL/responses" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"$GROK_BEDROCK_MODEL\",\"input\":\"Reply with the single word pong.\"}"
```

If `/responses` 404s or 400s, try `/chat/completions` with `{"model":"...","messages":[{"role":"user","content":"pong"}]}`. Note which path worked; that becomes `api_backend` in config (`responses` vs `chat_completions`).

### 2. Write `~/.grok/config.toml` **before** the first `grok` launch

If this file is missing, the TUI tries `auth.x.ai`. Put this at `~/.grok/config.toml`. Adjust `base_url` / `model` / `api_backend` to whatever step 1 proved.

```toml
[cli]
auto_update = false

disable_web_search = true

[models]
default = "grok-4.6-gov"
session_summary = "grok-4.6-gov"
web_search = "grok-4.6-gov"
image_description = "grok-4.6-gov"
allowed_models = ["grok-4.6-gov"]
disabled_models = ["grok-4.5", "grok-4.6"]

[model_providers.bedrock-gov]
base_url = "https://bedrock-mantle.us-gov-east-1.api.aws/openai/v1"
api_backend = "responses"
context_window = 500000

[model_providers.bedrock-gov.auth]
command = "/home/YOU/bin/grok-bedrock-token"
token_ttl_secs = 3600

[model.grok-4.6-gov]
model = "xai.grok-4.6"
name = "Grok 4.6 (GovCloud)"
model_provider = "bedrock-gov"
supports_backend_search = false
supports_reasoning_effort = true

[features]
telemetry = false
feedback = false
remote_fetch = false
managed_config = false
image_gen = false
video_gen = false
voice_mode = false
web_fetch = false
backend_tools = false
campaigns = false

[managed_mcps]
enabled = false

[memory]
enabled = false
```

Replace `/home/YOU/bin/grok-bedrock-token` with `$(realpath ~/bin/grok-bedrock-token)`. Use an absolute path; grok runs the command via `sh -c`.

Optional laptop pin (unsigned is enough for a spike):

```toml
# ~/.grok/requirements.toml
[cli]
auto_update = false

[features]
telemetry = false
remote_fetch = false
image_gen = false
video_gen = false

[models]
default = "grok-4.6-gov"
allowed_models = ["grok-4.6-gov"]
```

### 3. Build from source

Needs: git, rustup, cargo, python3 (for the helper). Toolchain pin is **1.94.0**.

```bash
# rustup (static.rust-lang.org). Skip if rustc 1.94+ already.
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"

git clone https://github.com/xai-org/grok-build.git
cd grok-build

# protoc: DotSlash fetches the zip from GitHub releases.
cargo install dotslash
command -v dotslash
# If cargo-install is painful, install protobuf-compiler from your distro
# and export PROTOC=$(command -v protoc)

cargo build -p xai-grok-pager-bin --release
# artifact: target/release/xai-grok-pager
mkdir -p ~/bin
ln -sf "$(pwd)/target/release/xai-grok-pager" ~/bin/grok
export PATH="$HOME/bin:$PATH"
```

Git crates that must resolve (both GitHub):

- `https://github.com/our-forks/async-openai.git`
- `https://github.com/helix-editor/nucleo.git`

Do **not** `cargo build` the whole workspace; it is slow. Always `-p xai-grok-pager-bin`.

Dev loop:

```bash
cargo check -p xai-grok-pager-bin
cargo run -p xai-grok-pager-bin -- -p "reply pong" -m grok-4.6-gov
```

### 4. First run

```bash
export PATH="$HOME/bin:$PATH"
export AWS_REGION=us-gov-east-1
export AWS_PROFILE=govcloud   # same as OpenCode
# export GROK_EXTRA_CA_BUNDLE=...

grok inspect --json | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('inspect ok')
"
# Confirm by eye: default model grok-4.6-gov, auto_update false, remote_fetch false,
# base_url is GovCloud not api.x.ai.

grok -p "Reply with the single word pong." -m grok-4.6-gov
```

If the TUI still offers a SpaceXAI login screen, config did not load. Check `$GROK_HOME` (default `~/.grok`) and that `config.toml` parses.

### 5. Egress check

Launch, send one prompt, let it compact if it wants. There must be **no** connections to `x.ai` / `api.x.ai` / `auth.x.ai`. Allowed: Bedrock, STS, and (during build only) github / crates.io / rustup.

```bash
# crude: while grok is running
ss -tnp | grep -E 'x\.ai|mixpanel' || echo "no x.ai sockets"
```

---

## Env vars cheat sheet

| Var | Required | Purpose |
| --- | --- | --- |
| `AWS_REGION` / `AWS_DEFAULT_REGION` | yes | GovCloud region for the helper and AWS CLI |
| `AWS_PROFILE` | if you use profiles | same as OpenCode |
| `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` (+ session token) | if no profile | same as OpenCode |
| `GROK_EXTRA_CA_BUNDLE` or `SSL_CERT_FILE` | if TLS intercept | extra roots; Grok already reads these |
| `GROK_HOME` | no | config/auth dir; default `~/.grok` |
| `RUST_LOG` + `GROK_LOG_FILE` | debug | `RUST_LOG=debug GROK_LOG_FILE=/tmp/grok.log grok` |
| `XAI_API_KEY` | **do not set** | would send a key at xAI-shaped URLs; we are BYOK via the helper |
| `GROK_MODELS_BASE_URL` | optional | only if you want the catalog fetch at `{url}/models`; keep `remote_fetch = false` anyway |

IAM: Mantle needs `bedrock-mantle:CreateInference` (or `AmazonBedrockMantleInferenceAccess`). Runtime needs `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream` on the Grok inference profile. The helper also needs whatever STS your keys already use.

---

## If `/responses` is wrong

Keep Mantle/Runtime `base_url`, change only:

```toml
[model_providers.bedrock-gov]
api_backend = "chat_completions"
```

If streaming tool calls 400:

```toml
[models]
stream_tool_calls = false
```

---

## Why this is not `grok login`

OpenCode (`anomalyco/opencode`) uses `@ai-sdk/amazon-bedrock` / `mantle` and the AWS SDK credential chain. Grok Build’s sampler only speaks OpenAI Chat Completions / Responses / Anthropic Messages over HTTPS with a **Bearer**. There is no SigV4 in the client.

`[model_providers.*.auth] command` is the supported contract: stdout is a bare token or `{"access_token":"...","expires_in":3600}`. stderr is for errors. `GROK_AUTH_EXPIRED=1` means refresh silently (the helper never prompts).

Do not reuse the baked-in catalog id `grok-4.6`: it still has `supports_backend_search = true` and xAI defaults. `grok-4.6-gov` + `allowed_models` / `disabled_models` is fail-closed so `/model` cannot pick `api.x.ai`. Custom `base_url`s are BYOK; session JWTs do not leak there.

---

## How this maps to OpenCode

| OpenCode (today) | Grok Build |
| --- | --- |
| `@ai-sdk/amazon-bedrock` + AWS SDK | OpenAI-compatible `base_url` + bearer helper |
| AWS keys / profile / SSO | same keys, consumed by `~/bin/grok-bedrock-token` |
| `opencode.json` provider block | `~/.grok/config.toml` (later `/etc/grok/managed_config.toml`) |
| npm / bun | `cargo build -p xai-grok-pager-bin --release` |
| models.dev catalog | local catalog only (`features.remote_fetch = false`) |

Grok 4.6 on GovCloud: 500k context, reasoning `low|medium|high|xhigh`, Chat Completions and Responses. Built-in Grok 4.6 already uses `api_backend = "responses"` and 500k — keep that; only retarget host and model id.

Prefer **Mantle + `xai.grok-4.6`**. Fall back to Runtime CRI (`us.xai.grok-4.6`) if Mantle is not entitled.

---

## Fleet files (when we ship to others)

Same TOML as `~/.grok/config.toml`, installed as:

- `/etc/grok/managed_config.toml` — defaults (user file can override cosmetics)
- `/etc/grok/requirements.toml` — pins (`cli.auto_update`, `features.telemetry`, `features.remote_fetch`, `features.image_gen`, `features.video_gen`, `models.default`, `models.allowed_models`)

Unsigned `$GROK_HOME/requirements.toml` is enough on a laptop. Fleet enforcement uses the signed / MDM path in Grok’s `26-config-reference.md`.

Ship: `xai-grok-pager` as `grok`, `grok-bedrock-token`, the two TOML files. `cli.auto_update = false` so it never phones home.

---

## Runtime egress

| Destination | Default | Intranet action |
| --- | --- | --- |
| Bedrock Mantle/Runtime GovCloud | needed | allow |
| STS / IAM | needed | allow |
| `api.x.ai`, `auth.x.ai`, `x.ai` | login, catalog, search, imagine, voice, embeddings | block + disable in config |
| Mixpanel / OTLP / trace upload | telemetry | `features.telemetry = false`; no trace upload URLs |
| `x.ai/cli` auto-update | on | `cli.auto_update = false` |
| Plugin marketplace / managed MCP | github / xAI | local skill dirs only; `managed_mcps.enabled = false` |
| `npx` MCP | npmjs | only if npm is allowed; prefer internal stdio binaries |
| Corp TLS intercept | — | `GROK_EXTRA_CA_BUNDLE` |

Tools that still call xAI even when the session model is custom: `web_search`, Imagine, voice STT, memory embeddings. Leave those features off. Memory can later run FTS-only with no embedding endpoint.

---

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Browser / `auth.x.ai` on launch | `~/.grok/config.toml` missing or not parsed; `GROK_HOME` wrong; ran `grok login` |
| 401 from Bedrock | helper failed; `AWS_PROFILE`/`AWS_REGION` unset in the grok process; IAM missing Mantle/Runtime |
| Helper prints traceback on stdout | grok treats stdout as the token. Fix the script so errors go to stderr and exit non-zero |
| 400 on stream / tools | set `api_backend = "chat_completions"` and/or `stream_tool_calls = false` |
| TLS errors | `GROK_EXTRA_CA_BUNDLE` to the corp root PEM |
| `protoc` / DotSlash fail | GitHub releases blocked for protobuf zip; install distro `protobuf-compiler` and set `PROTOC` |
| rustup / crates.io fail | you do not have the OSS sources we assumed; vendor on a less-restricted box and copy `target/release/xai-grok-pager` |
| Model picker still shows grok-4.5 / 4.6 | `allowed_models` / `disabled_models` not loaded; `grok inspect --json` |
| Slow full-workspace cargo | always `-p xai-grok-pager-bin` |

Debug:

```bash
RUST_LOG=debug GROK_LOG_FILE=/tmp/grok.log grok -p "pong" -m grok-4.6-gov
# grep the log for model, sampling, base_url, auth
```

---

## What we will not do in v1

- Native SigV4 inside `xai-grok-sampler` (internal fork later; upstream does not take PRs).
- LiteLLM / a shared proxy. AWS keys + the helper are enough.
- Web search, Imagine, voice until those have GovCloud replacements.
- SpaceXAI OIDC, deployment keys, or managed-config sync from `cli-chat-proxy`.

## Open items on the first spike

- Exact Mantle hostname (`*.api.aws` vs `*.amazonaws-us-gov.com`) and East vs West.
- Whether `/responses` streams tool calls; otherwise `chat_completions`.
- Token lifetime vs grok’s ~5 min refresh skew (`token_ttl_secs = 3600` is safe).
- Whether TLS inspection is in path.

## Key decisions

1. **Config + helper, not a fork.**
2. **New catalog id `grok-4.6-gov`.**
3. **Disable every xAI-hosted feature.**
4. **Build from source internally** (github + crates.io + rustup).
5. **Mantle first**, Runtime CRI as fallback.
