# Eval pitfalls

> Verified against promptfoo 0.124.1, lm-evaluation-harness v0.4.13, vLLM v0.31.0 docs, 2026-10-11

Most "the model got worse" or "the model is amazing" findings are eval bugs. Check these before believing a result.

## Contamination

- **Public benchmarks leak into training data.** A model that has seen the test set scores high without the skill. Treat public scores as weak evidence and prefer your own held-out set.
- **Your golden set can leak too:** pasted into a prompt library, used as few-shot examples, uploaded to a hosted eval viewer, or included in fine-tuning data. Track provenance and keep a hold-out split (`eval-strategy.md`).
- **Symptoms:** near-perfect scores on items that are hard for humans; verbatim reproduction of reference answers; big gap between public benchmark and your tasks.
- **Mitigations:** write fresh items after the model's training cutoff; paraphrase items and check the score holds; never fine-tune on eval items (`fine-tuning-llms`).

## Temperature, seed and non-determinism

- Compare at `temperature: 0` for gates; set `seed` anyway (promptfoo provider `config.seed`, lm-eval `seed` in `model_args` and `--seed`).
- Even greedy decoding is not bit-reproducible on most engines: batch composition and scheduling change floating-point reductions. vLLM documents reproducibility only with batch invariance (`VLLM_BATCH_INVARIANT=1`) on the same hardware and version.
- Some providers ignore `seed`; some reasoning models ignore or reject `temperature`. promptfoo omits `temperature` for models it recognizes as reasoning models.
- Always measure baseline-vs-baseline noise before calling a difference real.
- Response caches make reruns look perfectly stable; use `--no-cache` (promptfoo) and omit `--use_cache` (lm-eval) for gate runs.

## Prompt format and chat template mismatches

- **Server vs client templating:** chat endpoints apply the server's chat template. If you also apply one client-side (lm-eval `--apply_chat_template` on a completions endpoint already wrapping prompts, or a hand-built template string), the model sees nested templates.
- **Template drift:** a new engine version or updated `tokenizer_config.json` can change the template, BOS handling or default system prompt. Inspect a rendered prompt after any upgrade (many servers can echo the prompt or log it at debug level).
- **System prompt differences** between providers (some gateways inject one). Keep system prompts explicit in the eval config.
- **Stop sequences:** missing stops make the model ramble into the next turn; extra stops truncate valid answers. lm-eval tasks define `until` sequences; check samples with `--log_samples`.
- **Completions vs chat:** a base-model prompt sent to a chat endpoint, or a chat model on raw completions without a template, both degrade badly.

## Reasoning tokens

- Reasoning models emit thinking text. Depending on the server's reasoning parser it arrives as `reasoning_content`/`reasoning` or inline as `<think>...</think>` in `content`.
- promptfoo includes reasoning in the output by default (`Thinking: ...` prefix); set `showThinking: false` when assertions or judges must see only the answer.
- lm-eval `local-chat-completions` accepts `think_end_token` to strip reasoning before scoring.
- Reasoning consumes `max_tokens`. Too low a limit cuts the answer off, or leaves an unclosed `<think>` block that the parser cannot split.
- Add a guard assertion such as `not-icontains: "<think>"` in `defaultTest.assert`.
- Reasoning tokens count toward cost and latency; report output tokens alongside pass rate.

## Truncation

- **Input truncation:** prompts longer than the served context (`--max-model-len`, `-c`/`--ctx-size`) are rejected or truncated depending on the server. lm-eval's `max_length` defaults to 2048 for API models and can silently cut few-shot context.
- **Output truncation:** `max_tokens` / `max_gen_toks` too low; check `finish_reason == "length"` in raw responses.
- **Gateway limits:** LiteLLM or proxies may cap tokens or time out long generations; failures look like model errors.
- **Timeouts:** lm-eval API timeout defaults to 30 seconds; promptfoo retries HTTP errors (`maxRetries`, default 4). Slow local servers produce error rows that are not quality failures.

## Assertion bugs

- Case-sensitive `contains` where `icontains` was meant.
- Regexes that match the prompt echoed back.
- JSON checks failing on fenced code blocks; use `contains-json` or a `transform`.
- Expected values copied from one model's output style, penalizing equally correct answers.

## Comparing apples to oranges

- Different eval-set versions, few-shot counts, harness versions or task variants across runs.
- One side through a gateway with retries/fallbacks, the other direct. A fallback can silently serve a different model; check the `model` field in responses and gateway logs.
- Quantized judge for one run, full-precision judge for another.

## Official links

- promptfoo vLLM guide (reasoning, showThinking): https://www.promptfoo.dev/docs/providers/vllm/
- promptfoo OpenAI provider (defaults, reasoning models): https://www.promptfoo.dev/docs/providers/openai/
- lm-evaluation-harness API guide: https://github.com/EleutherAI/lm-evaluation-harness/blob/main/docs/API_guide.md
- vLLM reproducibility: https://docs.vllm.ai/en/latest/usage/reproducibility/
