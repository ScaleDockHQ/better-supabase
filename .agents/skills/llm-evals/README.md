# LLM Evals Skill

An agent skill for evaluating LLMs on your own tasks against any OpenAI-compatible endpoint: local servers, self-hosted engines behind a gateway, or cloud APIs. It packages golden-set design, model and endpoint comparison with [promptfoo](https://github.com/promptfoo/promptfoo), public benchmarks with [lm-evaluation-harness](https://github.com/EleutherAI/lm-evaluation-harness), LLM-as-judge done carefully, quality gates for numerics-changing changes (quantization, speculative decoding, KV-cache dtype, engine upgrades), and regression evals in CI.

## Install

```bash
npx skills add ScaleDockHQ/llm-skills --skill llm-evals
```

## Rules

- **Your tasks beat leaderboards.** Public benchmark scores are a prior, not a decision.
- **Same prompts, same sampling, same seed.** Otherwise it is not a comparison.
- **Gate numerics changes.** Quantization, speculative decoding, KV-cache dtype and engine upgrades need an A/B gate and a written decision.
- **Small and real before big and synthetic.** Fifty hand-checked real cases beat thousands of generated ones.
- **Judge the judge.** Calibrate any LLM judge against human labels; never let a model grade itself on a ship decision.
- **Keep eval data out of training data.** Hold out the golden set and track provenance.
- **Deterministic checks first.** Use model-graded checks only where nothing deterministic fits.
- **Record the run.** Config, model IDs, versions, sampling, results and decision, together.

## References

The `SKILL.md` overview is always loaded; the agent pulls a reference only when a step needs it.

- [`references/eval-strategy.md`](references/eval-strategy.md) — what to measure, golden-set design, sizing, slicing, provenance and hold-out.
- [`references/promptfoo.md`](references/promptfoo.md) — how promptfoo plugs into this stack; depth is in the `promptfoo` skill.
- [`references/lm-eval-harness.md`](references/lm-eval-harness.md) — how lm-evaluation-harness plugs into this stack (chat vs completions, logprobs); depth is in the `lm-evaluation-harness` skill.
- [`references/llm-as-judge.md`](references/llm-as-judge.md) — `llm-rubric`, judge configuration, thresholds, calibration, bias.
- [`references/quality-gates.md`](references/quality-gates.md) — perplexity and KL divergence vs task evals, A/B protocol, thresholds, decision record.
- [`references/regression-ci.md`](references/regression-ci.md) — CI tiers, gate policy, private endpoints and data; the workflow YAML lives in the `promptfoo` skill.
- [`references/pitfalls.md`](references/pitfalls.md) — contamination, temperature and non-determinism, chat template mismatches, reasoning tokens, truncation.

**Templates:**

- [`assets/promptfooconfig.yaml`](assets/promptfooconfig.yaml) — baseline vs candidate on two OpenAI-compatible endpoints, env-driven, identical sampling.
- [`assets/golden-set.example.jsonl`](assets/golden-set.example.jsonl) — promptfoo JSONL tests with metadata.

## Upstream credits

- [promptfoo](https://github.com/promptfoo/promptfoo) — eval runner, assertions and CI integration.
- [EleutherAI lm-evaluation-harness](https://github.com/EleutherAI/lm-evaluation-harness) — benchmark runner and OpenAI-compatible API models.
- [llama.cpp perplexity tool](https://github.com/ggml-org/llama.cpp/tree/master/tools/perplexity) — perplexity and KL divergence for quantization checks.
- [vLLM reproducibility docs](https://docs.vllm.ai/en/latest/usage/reproducibility/) — determinism and batch invariance.

## Companion skills

From [ScaleDockHQ/llm-skills](https://github.com/ScaleDockHQ/llm-skills); install any of them with `npx skills add ScaleDockHQ/llm-skills --skill <name>`:

- `inspect-ai`, `lighteval`, `deepeval`, `evalplus`, `swe-bench`, `guidellm`, `nvidia-aiperf` — eval runner and benchmark depth.
- `promptfoo` — task-eval runner in depth: config, assertions, CLI, CI workflow, quantization A/B gate.
- `lm-evaluation-harness` — public benchmarks in depth: endpoint model types, backends, tasks, results.
- `self-hosted-llms` — serving stacks; its "numerics-changing options need a quality gate" rule points here.
- `model-quantization` — quantized candidates; its quality checks send task evals here.
- `llm-gateway` — LiteLLM endpoints and keys the evals run through.
- `llm-observability` — production metrics and traces that feed new golden-set items.
- `fine-tuning-llms` — keep eval data out of training sets.
- `choosing-llm-hosting`, `local-llms`, `cloud-llms`, `llm-clients`, `self-hosted-genmedia` — where endpoints come from and how clients call them.

## License

MIT
