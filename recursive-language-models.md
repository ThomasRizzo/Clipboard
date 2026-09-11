# Recursive Language Models (RLMs)

Notes from a discussion of RLMs in the context of LLMs. RLMs here means **Recursive Language Models**, not "reasoning language models" (o1-style) and not reverse language models.

## What they are

RLMs are an **inference-time paradigm**, not a new transformer architecture. Same model weights; different way of running them.

Instead of stuffing a huge prompt into the context window, the full input is stored as a variable in a code sandbox (typically a Python REPL). The model writes code to inspect, slice, and decompose that input, then **recursively calls itself** on just the relevant snippets and stitches the results together.

That sidesteps context rot. Standard models degrade well before the hard window limit. RLMs have been shown handling inputs two orders of magnitude beyond the base window, and beating vanilla frontier models plus common long-context scaffolds on hard tasks (including pairwise comparisons over millions of tokens) at comparable cost.

A small post-trained model from the paper, **RLM-Qwen3-8B**, improved about **28%** over base Qwen3-8B on the authors' long-context suite.

Core loop:

1. Put the prompt in an environment variable, not in the model's token budget.
2. The LM writes code (`repl` blocks) to explore it.
3. Code runs in the sandbox; stdout / errors come back as observations.
4. `llm_query()` / recursive sub-calls handle chunks.
5. The model finishes with `FINAL(answer)` or `FINAL_VAR(name)`.

## Primary sources

- Paper: [Recursive Language Models](https://arxiv.org/abs/2512.24601) — Alex L. Zhang, Tim Kraska, Omar Khattab (MIT CSAIL / OASYS). arXiv:2512.24601
- Blog: [https://alexzhang13.github.io/blog/2025/rlm/](https://alexzhang13.github.io/blog/2025/rlm/)
- Docs: [https://alexzhang13.github.io/rlm/](https://alexzhang13.github.io/rlm/)
- HTML paper: [https://arxiv.org/html/2512.24601](https://arxiv.org/html/2512.24601)
- Overview site: [https://rlm.md/](https://rlm.md/) (unofficial explainer, including [RLM vs LLM](https://rlm.md/rlm-vs-llm.html))
- Post-trained weights: [mit-oasys/rlm-qwen3-8b-v0.1](https://huggingface.co/mit-oasys/rlm-qwen3-8b-v0.1) on Hugging Face

Quick start with the official package:

```bash
pip install rlms
```

```python
from rlm import RLM

rlm = RLM(
    backend="openai",
    backend_kwargs={"model_name": "gpt-4o"},
)
result = rlm.completion("Your long-context task here")
print(result.response)
```

## Official libraries (authors)

These are the ones to start with.

| Project | Link | Notes |
| --- | --- | --- |
| **rlm** (official) | [github.com/alexzhang13/rlm](https://github.com/alexzhang13/rlm) | Plug-and-play inference engine + training env. Multiple sandboxes. PyPI: `rlms`. |
| **rlm-minimal** | [github.com/alexzhang13/rlm-minimal](https://github.com/alexzhang13/rlm-minimal) | Stripped-down core so you can read and fork the idea quickly. |

## Independent Python implementations

| Project | Link | Notes |
| --- | --- | --- |
| **minrlm** | [github.com/avilum/minrlm](https://github.com/avilum/minrlm) | Small, pip-installable (`pip install minrlm`). File analysis without stuffing data into the prompt. Includes RLM-Bench. |
| **replm** | [github.com/dschulmeist/replm](https://github.com/dschulmeist/replm) | Lightweight wrapper around any OpenAI-compatible client. `uv add replm`. |
| **recursive-llm** (grishahq) | [github.com/grishahq/recursive-llm](https://github.com/grishahq/recursive-llm) | Practical Python library: provider portability, budgets, traces. |
| **rlm-core** | [pypi.org/project/rlm-core](https://pypi.org/project/rlm-core/) | Async inference engine on PyPI (`pip install rlm-core`). |
| **kmad/rlm** | [github.com/kmad/rlm](https://github.com/kmad/rlm) | LiteLLM-backed CLI + Python API. Separate root / sub-models. |
| **Ray0907/rlm** | [github.com/Ray0907/rlm](https://github.com/Ray0907/rlm) | LiteLLM backends including Ollama. |
| **mini-rlm** | [github.com/Shuyib/mini-rlm](https://github.com/Shuyib/mini-rlm) | Small toolkit (`rlm(query, context)`). |
| **rlm-paper-implementation** | [github.com/AKMessi/rlm-paper-implementation](https://github.com/AKMessi/rlm-paper-implementation) | Multi-provider app aimed at long documents (PDF, DOCX, etc.). |
| **pysprings/rlm** | [github.com/pysprings/rlm](https://github.com/pysprings/rlm) | Teaching implementation (~77 lines) plus Gutenberg demo. |
| **rlm-reproduction** | [github.com/drbillwang/rlm-reproduction](https://github.com/drbillwang/rlm-reproduction) | Reproduction + depth=2 experiments on S-NIAH / OOLONG. |

## Other languages and variants

| Project | Link | Notes |
| --- | --- | --- |
| **recursive-llm** (mepuka) | [github.com/mepuka/recursive-llm](https://github.com/mepuka/recursive-llm) | Effect TypeScript on Bun. Multi-provider, budgets, traces. |
| **RLM** (Elixir) | [github.com/Jbollenbacher/RLM](https://github.com/Jbollenbacher/RLM) | Elixir host, Python REPL for the data plane. |
| **rlm-rs** | [github.com/zircote/rlm-rs](https://github.com/zircote/rlm-rs) | Rust CLI implementing the RLM pattern (Claude Code oriented). |
| **λ-RLM** | [github.com/lambda-calculus-LLM/lambda-RLM](https://github.com/lambda-calculus-LLM/lambda-RLM) | Typed / combinator variant instead of free-form REPL code. |

GitHub topic dump: [topic:recursive-language-model](https://github.com/topics/recursive-language-model).

## What *not* to confuse this with

The acronym RLM is overloaded:

- **Reasoning Language Models / Large Reasoning Models** (o1, R1, QwQ) — think-then-answer models trained with RL. Different thing.
- **Reverse Language Models** — generate / score tokens conditioned on *future* context.
- **LLM-enhanced RL** / RLLM reward-model work — reinforcement learning *around* language models.
- Some repos named `rlm` are generic recursive task decomposers and are **not** implementations of the Zhang/Kraska/Khattab paper.

## Practical takeaway

Start with **[alexzhang13/rlm](https://github.com/alexzhang13/rlm)** (`pip install rlms`). Use **[rlm-minimal](https://github.com/alexzhang13/rlm-minimal)** if you want to read the whole loop in a few files. **[minrlm](https://github.com/avilum/minrlm)** and **[replm](https://github.com/dschulmeist/replm)** are the cleanest independent Python packages for trying the idea on real files without adopting the full official stack.
