# OpenCode System Prompts

Links to the system prompts used by [anomalyco/opencode](https://github.com/anomalyco/opencode) (dev branch) for different models.

These are selected and applied via plugins in `packages/core/src/plugin/optimize.ts` based on model ID matching. A base harness prompt is always present; model-specific ones override or append.

## Base / Harness Prompt

Used as the starting system prompt (rendered with tool guidance):

- [packages/core/src/session/runner/prompt/system.txt](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/session/runner/prompt/system.txt)

## Model-Specific Prompts

Located in `packages/core/src/plugin/system-prompt/`:

| Models / Match | Prompt File | Link |
|----------------|-------------|------|
| Claude (Anthropic) | anthropic.txt | [anthropic.txt](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/plugin/system-prompt/anthropic.txt) |
| GPT (OpenAI, non-Astra) | gpt.txt | [gpt.txt](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/plugin/system-prompt/gpt.txt) |
| GPT Astra | gpt-astra.txt | [gpt-astra.txt](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/plugin/system-prompt/gpt-astra.txt) |
| Kimi | kimi.txt | [kimi.txt](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/plugin/system-prompt/kimi.txt) |
| Trinity / Arcee | trinity.txt | [trinity.txt](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/plugin/system-prompt/trinity.txt) |
| Muse (Meta) | meta.txt | [meta.txt](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/plugin/system-prompt/meta.txt) |

### Notes

- **Anthropic/Claude**: Appends the content of `anthropic.txt` (currently focused on code comment guidance).
- **Others**: Typically override the base system prompt with the model-specific file.
- Selection logic is in `packages/core/src/plugin/optimize.ts` (OpenAIPlugin, AnthropicPlugin, KimiPlugin, ArceePlugin, MetaPlugin).
- For most other models, the base `system.txt` is used without a dedicated override.
- Older versions of OpenCode (pre-v2 restructuring) had more prompts under `packages/opencode/src/session/prompt/` (e.g. beast.txt, gemini.txt, codex.txt, default.txt). See tags like `v1.18.32` for historical files.

Repo: https://github.com/anomalyco/opencode
