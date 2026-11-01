# lm-evaluation-harness

> Verified against lm-evaluation-harness v0.4.13, 2026-10-11

Depth: install the lm-evaluation-harness skill (npx skills add ScaleDockHQ/llm-skills --skill lm-evaluation-harness)

## How it plugs into this stack

lm-evaluation-harness supplies public-benchmark numbers: a prior when choosing models, and one extra screen in a quality gate (`quality-gates.md`). It never replaces the golden-set eval (`promptfoo.md`). Stack-specific rules:

- **Endpoint types.** Generative tasks (GSM8K, IFEval) run through `local-chat-completions` with `--apply_chat_template`. Loglikelihood and multiple-choice tasks (MMLU, HellaSwag) need `local-completions` and an endpoint that returns prompt logprobs with `echo`; a chat endpoint cannot run them. Test logprobs with the `curl` check in `SKILL.md` first.
- **URLs and keys.** `base_url` is the full endpoint URL (`.../v1/chat/completions`), unlike promptfoo's `/v1` root. The key goes in `OPENAI_API_KEY`, never in `--model_args`.
- **Tokenizer.** Gateway aliases are not Hugging Face repos: set `tokenizer=<repo>` explicitly for completions runs.
- **Smoke before full.** `--limit 20 --log_samples`, read the samples, then run without `--limit`. Never report `--limit` numbers.
- **Comparisons.** Same harness version, few-shot, chat-template flags, `gen_kwargs` and seed on both sides; run the baseline on the same version.
- **Contamination.** A public-benchmark gain is not a product gain (`pitfalls.md`).
