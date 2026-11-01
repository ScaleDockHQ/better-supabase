---
name: llm-evals
description: Evaluate LLMs on your own tasks against any OpenAI-compatible endpoint (local llama.cpp/Ollama, self-hosted vLLM/SGLang behind LiteLLM or llama-swap, or a cloud API). Use when choosing between models or endpoints, building a golden set from real prompts, A/B testing two deployments, quality-gating a numerics-changing change (quantization, speculative decoding, KV-cache dtype, new engine or chat template version), running standard benchmarks with lm-evaluation-harness (local-completions, local-chat-completions), writing promptfoo configs and assertions, using LLM-as-a-judge (llm-rubric) safely, adding regression evals to CI (GitHub Actions), or debugging eval results that look wrong (contamination, temperature, chat template mismatch, reasoning tokens, truncation, perplexity or KL divergence vs task accuracy).
license: MIT
metadata:
  author: ScaleDockHQ
  version: "1.2.0"
compatibility: Needs an OpenAI-compatible /v1 endpoint, curl and jq. promptfoo runs via npx (Node.js). lm-evaluation-harness is an upstream Python CLI (lm_eval) installed separately. Works for local, self-hosted, gateway and cloud endpoints.
---

# LLM Evals

Measure whether a model, endpoint or serving change is good enough **for your tasks**, with evidence you can repeat. This skill covers task evals (promptfoo), standard benchmarks (lm-evaluation-harness), LLM-as-judge, quality gates for numerics-changing changes, and regression evals in CI.

**Scope.** In: designing eval sets, running evals against OpenAI-compatible endpoints, comparing two models or endpoints, gating quantization / speculative decoding / KV-cache / engine upgrades, CI regression. Out: serving setup (see `self-hosted-llms`, `local-llms`), how to quantize (see `model-quantization`), training (see `fine-tuning-llms`), production monitoring (see `llm-observability`).

Load the reference a step names; do not improvise flags or config keys that are not in a reference or in upstream docs.

## Discover first

Run these read-only checks before asking anything. Never print keys: test for presence only.

```bash
# Existing eval assets in the repo
ls promptfooconfig.* evals/ eval/ tests/evals/ .promptfoo/ 2>/dev/null
find . -maxdepth 3 \( -name 'promptfooconfig*.y*ml' -o -name '*.jsonl' -o -name 'lm_eval*' -o -name '*golden*' \) -not -path './node_modules/*' 2>/dev/null | head -50
ls .github/workflows/ 2>/dev/null && grep -l -i -E 'promptfoo|lm_eval' .github/workflows/* 2>/dev/null

# Installed tools
command -v node npx jq curl lm_eval 2>/dev/null
node --version 2>/dev/null

# Endpoint and models (base URL from env or ask once; key only via env)
echo "${LLM_BASE_URL:-unset}"; [ -n "${LLM_API_KEY:-}" ] && echo "LLM_API_KEY is set" || echo "LLM_API_KEY not set"
curl -fsS -H "Authorization: Bearer ${LLM_API_KEY:-none}" "${LLM_BASE_URL:-http://localhost:8000/v1}/models" | jq -r '.data[].id'

# Does the endpoint return logprobs on /v1/completions? (needed for loglikelihood benchmarks)
curl -fsS -H "Authorization: Bearer ${LLM_API_KEY:-none}" -H 'Content-Type: application/json' \
  "${LLM_BASE_URL:-http://localhost:8000/v1}/completions" \
  -d '{"model":"<model-id>","prompt":"Hello","max_tokens":1,"logprobs":1,"echo":true}' | jq '.choices[0].logprobs != null'
```

Ask only what discovery cannot answer:

1. What decision does this eval support (pick a model, ship a change, block a regression)?
2. What are 20–200 real inputs and what does "good" look like for each?
3. Which endpoints/model IDs are baseline and candidate?
4. Are any inputs sensitive (PII, customer data)? If yes, where may eval outputs be stored?

## Decision flow

```
What are you deciding?
├─ "Which model/endpoint for my use case?"    → golden set + promptfoo, compare N providers  (eval-strategy, promptfoo)
├─ "Did this numerics change hurt quality?"   → A/B quality gate, same prompts/sampling/seed (quality-gates)
│    └─ have local weights + llama.cpp?       → add KL divergence / perplexity as an early signal (quality-gates)
├─ "How does it score on public benchmarks?"  → lm-evaluation-harness against the endpoint    (lm-eval-harness)
│    ├─ multiple-choice / loglikelihood task? → local-completions + logprobs support required
│    └─ generative task on chat model?        → local-chat-completions + --apply_chat_template
├─ "Open-ended outputs, no exact answer"      → llm-rubric with a calibrated judge           (llm-as-judge)
├─ "Stop regressions on every PR"             → promptfoo in GitHub Actions                  (regression-ci)
└─ "Results look wrong / noisy"               → pitfalls checklist                           (pitfalls)
```

## Rules

- **Your tasks beat leaderboards.** Public benchmark scores are a prior, not a decision. Decide on a golden set built from your real inputs.
- **Same prompts, same sampling, same seed.** A comparison is only valid if prompts, chat template, system prompt, temperature, max tokens and seed are identical on both sides. Pin them in config, not in someone's shell.
- **Gate numerics changes.** Quantization, speculative decoding, KV-cache dtype, attention backend, engine or chat-template upgrades all need an A/B quality gate with a written decision before they reach users.
- **Small and real before big and synthetic.** Fifty hand-checked real cases beat five thousand generated ones. Grow the set from production failures.
- **Judge the judge.** An LLM judge is a model under test too: check it against human labels, pin its model and prompt, and never let a model judge itself on a ship decision.
- **Keep eval data out of training data.** Hold out the golden set, track where every item came from, and never fine-tune on it.
- **Deterministic checks first.** Prefer `equals`, `contains`, `regex`, `is-json` and schema checks; use model-graded checks only where no deterministic check exists.
- **Record the run.** Store config, model IDs, endpoint versions, sampling and results with the decision. An unrecorded eval did not happen.

## Workflows

### 1. Build a golden set from real tasks

- [ ] Collect 20–200 real inputs from logs, tickets or user sessions; strip or replace PII before copying (see `llm-observability` privacy guidance).
- [ ] For each item write the expected property, not the expected essay: a fact that must appear, a format, a refusal, a tool call.
- [ ] Tag items with `metadata` (source, category, difficulty, `critical: "yes"` for must-not-regress).
- [ ] Store as promptfoo JSONL tests, one per line; start from `assets/golden-set.example.jsonl`.
- [ ] Hand-run 5 items and read the outputs before trusting any automatic score.
- [ ] Record provenance and the hold-out rule. → `references/eval-strategy.md`

### 2. Compare two models or endpoints

- [ ] Confirm both model IDs via `/v1/models` on each endpoint.
- [ ] Copy `assets/promptfooconfig.yaml`; set `BASELINE_*` and `CANDIDATE_*` env vars; keep sampling identical.
- [ ] `npx promptfoo@0.124.1 eval -c promptfooconfig.yaml --no-cache -o results.json -o report.html` (pin the version you verified; the `promptfoo` skill has the details).
- [ ] Look at per-item flips (pass→fail and fail→pass), not only the aggregate pass rate.
- [ ] Repeat with `--repeat` on a subset to see run-to-run noise before calling a difference real. → `references/promptfoo.md`, `references/quality-gates.md`

### 3. Quality-gate a numerics change

- [ ] Write the gate **before** running: metric, threshold, critical items, who decides. Use the decision record in `references/quality-gates.md`.
- [ ] Baseline = current production config; candidate = exactly one change (quant level, draft model, KV dtype, engine version).
- [ ] Same prompts, same sampling, same seed, same max tokens, same chat template on both.
- [ ] Run task evals (promptfoo) on the golden set; optionally add a benchmark subset (lm-eval) and KL divergence (llama.cpp `llama-perplexity`) when you have both weight files.
- [ ] Measure noise: run baseline against itself; a delta inside baseline-vs-baseline noise is not a regression.
- [ ] Decide pass / fail / pass-with-conditions, write it down, link the results. → `references/quality-gates.md`

### 4. Run standard benchmarks

- [ ] `pip install "lm_eval[api]"` in an isolated environment (upstream Python CLI).
- [ ] Pick the model type: `local-completions` for loglikelihood / multiple-choice tasks (needs logprobs), `local-chat-completions` + `--apply_chat_template` for generative tasks on chat endpoints.
- [ ] Pass the key via `OPENAI_API_KEY="$LLM_API_KEY"` in the environment, never in `--model_args`.
- [ ] Start with `--limit 20 --log_samples` and read samples to confirm answer extraction works.
- [ ] Run full tasks only after the smoke run looks right; save `--output_path` results with the config. → `references/lm-eval-harness.md`

### 5. LLM-as-judge

- [ ] Use only where deterministic assertions cannot express "good".
- [ ] Configure the judge once in `defaultTest.options.provider`; pin model and temperature 0; set `showThinking: false` for reasoning judges.
- [ ] Write rubrics as pass/fail criteria with a `threshold`.
- [ ] Calibrate on 20–50 human-labelled items; report agreement before using the judge for decisions.
- [ ] Use a judge from a different model family than the candidate. → `references/llm-as-judge.md`

### 6. Regression evals in CI

- [ ] Commit the config and golden set; keep secrets in CI secrets.
- [ ] Run a small, fast, deterministic subset on every PR; run the full set nightly or before release.
- [ ] Fail on promptfoo exit code (100 = test failures) or on a pass-rate threshold via `PROMPTFOO_PASS_RATE_THRESHOLD`.
- [ ] Upload results as artifacts; do not use public share links for private data. → `references/regression-ci.md`

### 7. Troubleshoot

- [ ] Scores collapse after a change → check chat template, stop sequences, truncation and `max_tokens` first.
- [ ] Outputs contain `<think>` or reasoning text → reasoning parser or `showThinking` settings.
- [ ] Results differ between identical runs → temperature, seed, batching non-determinism, caching.
- [ ] Benchmark score suspiciously high → contamination. → `references/pitfalls.md`

## Reference index

| Reference                       | Load when                                                                                                                    |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `references/eval-strategy.md`   | Designing what to measure, golden sets, sizing, provenance and hold-out                                                      |
| `references/promptfoo.md`       | How promptfoo plugs into this stack; points to the `promptfoo` skill for depth                                               |
| `references/lm-eval-harness.md` | How lm-evaluation-harness plugs into this stack (chat vs completions, logprobs); points to the `lm-evaluation-harness` skill |
| `references/llm-as-judge.md`    | Model-graded assertions, judge selection, calibration, bias                                                                  |
| `references/quality-gates.md`   | Gating quantization, speculative decoding, KV-cache dtype, engine upgrades; KL divergence vs task evals; decision record     |
| `references/regression-ci.md`   | CI tiers, gate policy, private endpoints and data; workflow YAML lives in the `promptfoo` skill                              |
| `references/pitfalls.md`        | Contamination, temperature, chat template mismatches, reasoning tokens, truncation                                           |

Templates: `assets/promptfooconfig.yaml` (baseline vs candidate, OpenAI-compatible, env-driven), `assets/golden-set.example.jsonl` (promptfoo JSONL tests).

## Companion skills

Install any of them with `npx skills add ScaleDockHQ/llm-skills --skill <name>`.

- `promptfoo` — depth on the task-eval runner: config, assertions, CLI, CI workflow, quantization A/B gate.
- `lm-evaluation-harness` — depth on public benchmarks: endpoint model types, backends, tasks, results.
- `inspect-ai` — agent and benchmark evals with Inspect.
- `lighteval` — Hugging Face benchmark runner.
- `deepeval` — pytest-style LLM unit tests and metrics.
- `evalplus` — HumanEval+ and MBPP+ code benchmarks.
- `swe-bench` — repository-level software-engineering benchmark.
- `guidellm` — load and latency benchmarks of OpenAI-compatible servers.
- `nvidia-aiperf` — NVIDIA AIPerf serving benchmarks.
- `self-hosted-llms` — serving stacks whose numerics changes this skill gates.
- `model-quantization` — produces the quantized candidates; send task evals here.
- `llm-gateway` — LiteLLM endpoint and keys that evals run through.
- `llm-observability` — production signals that feed new golden-set items.
- `fine-tuning-llms` — keep this skill's golden set out of training data.
- `choosing-llm-hosting`, `local-llms`, `cloud-llms`, `llm-clients` — where the endpoints under test come from.
