# Structured outputs: quality gate and pitfalls

> Verified against vLLM v0.31.0 (docs: features/structured_outputs, features/tool_calling), SGLang v0.5.21 (docs: advanced_features/structured_outputs), llama.cpp v0.6.0 (grammars/README.md), Ollama v0.40.3 (docs: capabilities/structured-outputs), TensorFold v1.0.7 (docs/api.md), 2026-10-11

Constrained decoding masks tokens so the output matches a grammar. That guarantees syntax, not meaning: the model can still fill valid fields with wrong values, and a changed backend, schema or engine version can change which tokens are allowed. Treat any change to the constraint path as a numerics-and-validity change and gate it.

Install the eval skill if it is missing: `npx skills add ScaleDockHQ/llm-skills --skill llm-evals`.

## Gate procedure

Write the thresholds before running anything.

1. **Golden set.** 50 to 200 real prompts for the task, each with its schema and a reference answer or a deterministic check. Include hard cases: long inputs, optional fields, nested arrays, enums, empty results, non-English text.
2. **Baseline arm.** Current production path: same model, same engine, same sampling, schema described in the prompt, no constraint (or the current constraint). Run each prompt at least 3 times (more at temperature above 0). Record:
   - schema-validity rate (parse plus validate against the schema; `is-json` with a schema in promptfoo, see `llm-evals`);
   - task accuracy (field-level match against the reference, or the task's own metric);
   - finish reasons (`length` counts as invalid), output tokens per request, p50 and p95 latency, first-request latency after a cold start.
3. **Candidate arm.** Exactly one change: constraint on, a different backend, a different schema, or a new engine version. Same prompts, seeds and sampling.
4. **Compare per item**, not only in aggregate: list pass-to-fail and fail-to-pass flips and read them.
5. **Decide against the thresholds you wrote.** A reasonable default is: validity rate not lower than baseline and at least your product requirement; task accuracy not worse than baseline by more than the run-to-run noise you measured; no new `length` truncations; cold-start and p95 latency inside budget. Write the decision with links to the results.
6. **Roll back** by removing the constraint flag or request field (or reverting the backend flag) and restarting the engine; keep the baseline config in version control so the rollback is one commit.

Gate again after: an engine upgrade, a backend change (`auto` can pick differently per release), a schema edit, a model or quant change, a chat-template change, or enabling thinking.

## Pitfalls

- **Describe the schema in the prompt as well.** vLLM, SGLang and Ollama docs say to; llama.cpp states the schema "is not injected into the prompt", so the model cannot see it. Constraint-only prompting forces tokens the model did not plan for.
- **Truncation is invalid output.** A reply cut at `max_tokens` is an incomplete value (`finish_reason: "length"`). Raise `max_tokens`, and when thinking is on remember reasoning tokens count against it.
- **Thinking models.** With a reasoning parser the grammar applies after the reasoning ends (vLLM, TensorFold). vLLM can leave structured output disabled when reasoning is not parsed into its own field; the escape hatch is `--structured-outputs-config.enable_in_reasoning=True`. Test thinking on and off.
- **Schema subsets differ by engine.** llama.cpp silently skips unsupported keywords and defaults `additionalProperties` to `false`; test the exact schema on the exact engine, and keep schemas in OpenAI strict style (all properties required, `additionalProperties: false`, optional fields as `["string","null"]`).
- **Regex dialect.** vLLM backends `xgrammar`, `guidance` and `outlines` use Rust-style regex; `lm-format-enforcer` uses Python `re`. A pattern tested in one may fail in another.
- **Cold compile.** The first request with a new schema pays grammar compile time (vLLM documents "several seconds or more"; then cached). Warm the schemas you use at startup and exclude the first request from latency gates.
- **Backend `auto` is a moving target** in vLLM; pin `--structured-outputs-config.backend` once you have gated one.
- **Whitespace.** `--structured-outputs-config.disable_any_whitespace` (xgrammar, guidance) forces compact JSON; TensorFold allows at most 32 blank characters between JSON tokens.
- **Tools and constraints together.** On vLLM, `tool_choice` named or `required` already uses the structured-output backend. TensorFold rejects a grammar sent with `tool_choice: "required"` or a named function (HTTP 400).
- **Ollama Cloud** does not support structured outputs; local only.
- **Client libraries.** Pydantic `model_json_schema()` and Zod `z.toJSONSchema()` output can contain keywords a given engine skips; validate the generated schema on the engine before trusting it.

## Official links

- https://docs.vllm.ai/en/latest/features/structured_outputs/
- https://docs.sglang.ai/advanced_features/structured_outputs.html
- https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md
- https://docs.ollama.com/capabilities/structured-outputs
- https://github.com/ashhart/TensorFold/blob/main/docs/api.md
