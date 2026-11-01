# promptfoo

> Verified against promptfoo 0.124.1, 2026-10-11

Depth: install the promptfoo skill (npx skills add ScaleDockHQ/llm-skills --skill promptfoo)

## How it plugs into this stack

promptfoo is the runner for task evals on the golden set (`eval-strategy.md`), the A/B runner for gates (`quality-gates.md`) and the CI gate (`regression-ci.md`). Stack-specific rules:

- **Endpoints.** Every OpenAI-compatible endpoint in this stack (llama.cpp, Ollama, vLLM, SGLang, LiteLLM or llama-swap, cloud) is reached with `openai:chat:<model>` and `apiBaseUrl` set to the `/v1` root. The model ID is whatever `GET /v1/models` returns, including gateway aliases.
- **Keys.** `apiKeyEnvar: NAME` reads a key from the environment; use `apiKeyRequired: false` for open local servers. Never inline keys in the config.
- **Baseline versus candidate.** One config, two providers labelled `baseline` and `candidate`, identical `temperature`, `top_p`, `max_tokens` and `seed` (`assets/promptfooconfig.yaml`).
- **Gate runs.** `--no-cache`, `--no-share`, pinned `npx promptfoo@<version>`; per-item flips (pass to fail, fail to pass) matter more than the aggregate rate.
- **Reasoning models.** Thinking text breaks `equals` and judges: `showThinking: false`, enough `max_tokens`, same thinking settings on both sides.
- **Judges.** A separate grader provider under `defaultTest.options.provider`; never the model under test (`llm-as-judge.md`).
- **Exit codes.** `0` pass, `100` failures or pass rate below `PROMPTFOO_PASS_RATE_THRESHOLD`, `1` other errors.

Use `lm-eval-harness.md` instead for public benchmarks.
