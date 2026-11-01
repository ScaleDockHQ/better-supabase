# Quality gates for numerics-changing changes

> Verified against llama.cpp v0.6.0 (tools/perplexity), vLLM v0.31.0 docs (reproducibility, batch invariance), promptfoo 0.124.1, lm-evaluation-harness v0.4.13, 2026-10-11

A quality gate is a pre-agreed test that a serving change must pass before it reaches users. It applies to any change that alters the numbers the model computes, even when "it should be lossless".

## What counts as a numerics change

- Weight quantization (GGUF K-quants, AWQ, GPTQ, FP8, NVFP4, …) or a different quant of the same model.
- KV-cache dtype (e.g. FP8 KV cache) or KV offload.
- Speculative decoding (draft model, MTP, n-gram); lossless in theory, but implementation bugs and sampling differences are real.
- Attention backend, kernel or CUDA graph changes.
- Engine version upgrades (vLLM, SGLang, llama.cpp, TensorRT-LLM).
- Chat template or tokenizer changes, including a new `tokenizer_config.json` from the model repo.
- Tensor/pipeline parallel layout changes.

Changes that are _not_ numerics changes still need a smoke eval (routing, gateway config, timeouts).

## Signals: distribution metrics vs task evals

| Signal                                  | Tool                               | What it tells you                                                                                         | Limits                                                                                          |
| --------------------------------------- | ---------------------------------- | --------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Perplexity (PPL)                        | `llama-perplexity`                 | Next-token prediction on a corpus                                                                         | Not comparable across tokenizers or projects; fine-tunes can have higher PPL and better quality |
| KL divergence (KLD) vs reference logits | `llama-perplexity --kl-divergence` | How far the candidate's token distribution moved from the reference                                       | Needs both models locally and a large logits file; says nothing about task success              |
| Same-top-token %, Δp percentiles        | same run                           | How often the greedy token changes; whether shifts are noise (symmetric) or degradation (skewed negative) | Same as KLD                                                                                     |
| Benchmark subset                        | lm-evaluation-harness              | Comparable public metric                                                                                  | Contamination; may not reflect your use                                                         |
| Task eval on golden set                 | promptfoo                          | Whether _your_ outputs still pass                                                                         | Smaller sample, needs a good set                                                                |

Use distribution metrics as an **early, cheap screen** (reject clearly bad quants fast) and task evals as the **decision**. A low KLD does not prove task quality; a high one is a strong reason to stop.

### KL divergence with llama.cpp

```bash
# 1. Record reference logits from the higher-precision model (file can be tens of GiB)
llama-perplexity -m model-bf16.gguf -f wiki.test.raw --kl-divergence-base ref-logits.kld
# 2. Compare the candidate quant against those logits
llama-perplexity -m model-q4_k_m.gguf --kl-divergence-base ref-logits.kld --kl-divergence
```

The output includes mean KLD, PPL ratio and difference, mean and percentile Δp of the correct token, RMS Δp and "Same top p". The llama.cpp convention is the Wikitext-2 test set (`scripts/get-wikitext-2.sh` in the repo); use domain text too if you have it. `llama-perplexity` also offers `--hellaswag`, `--winogrande` and `--multiple-choice` for quick local task scores.

For non-GGUF engines, run the same golden set and a benchmark subset through the endpoint instead.

## A/B protocol

1. **Freeze the baseline.** Current production model, quant, engine version, flags and chat template. Record them.
2. **One change at a time.** The candidate differs in exactly one numerics dimension.
3. **Identical requests.** Same golden-set version, prompts, system prompt, chat template, `temperature`, `top_p`, `max_tokens`, `seed`, stop sequences. Use one promptfoo config with two providers (`assets/promptfooconfig.yaml`).
4. **Greedy where possible.** Use `temperature: 0` for gate runs so differences come from numerics, not sampling. If production samples, add a second run at production settings with `--repeat`.
5. **Measure noise.** Run baseline vs baseline (two runs, or `--repeat 3` on a subset). Batching and scheduling make many engines non-deterministic even at temperature 0; vLLM only guarantees reproducibility with batch invariance enabled (`VLLM_BATCH_INVARIANT=1`) on the same hardware and version. The baseline-vs-baseline flip count is your noise floor.
6. **Run the candidate** with `--no-cache` and capture `results.jsonl` per provider.
7. **Compare per item.** Count regressions (pass→fail) and fixes (fail→pass); inspect every regression on `critical` items by reading the outputs (per-item diff recipe and script in the promptfoo skill: `npx skills add ScaleDockHQ/llm-skills --skill promptfoo`, `references/combos/quant-ci-gate.md`).
8. **Check non-quality effects** in the same run: latency, tokens/s, output length, error rate. A quant that changes output length changes cost and latency too.
9. **Decide and record** using the decision record below.

## Thresholds

Agree on thresholds **before** the candidate run; never tune them after seeing results. A workable starting policy (adapt to your risk):

- Zero regressions on `critical: "yes"` items that are not explained by noise and reviewed by a human.
- Net regressions on the whole set no larger than the baseline-vs-baseline noise floor.
- No new format failures (JSON, tool calls), since these break integrations outright.
- Distribution screen (when available): candidate KLD and same-top-token % no worse than the previous accepted quant level for this model.
- Latency / throughput targets met (otherwise the change has no point).

Write thresholds as counts of items, not only percentages, so small sets are not misread.

## Decision record

Store next to the results (markdown in the repo or the ticket):

```markdown
# Quality gate: <change summary>

- Date: <YYYY-MM-DD> Owner: <name>
- Decision: PASS | FAIL | PASS WITH CONDITIONS
- Baseline: <model id>, <quant>, <engine + version>, <key flags>, chat template <hash or version>
- Candidate: <same fields; highlight the one change>
- Eval set: <path>@<git sha>, <N> items (<M> critical)
- Sampling: temperature=<>, top_p=<>, max_tokens=<>, seed=<>
- Noise floor (baseline vs baseline): <flips>/<N>
- Results: baseline pass <a>/<N>, candidate pass <b>/<N>; regressions <r> (critical <rc>), fixes <f>
- Distribution screen (optional): mean KLD <>, same-top-token <>%
- Benchmark subset (optional): <task>: baseline <>, candidate <>
- Latency/throughput: <summary>
- Reviewed regressions: <list of item ids and verdicts>
- Conditions / follow-ups: <e.g. monitor error rate for 7 days, re-run with full set>
- Artifacts: <links to results.json, report.html>
```

## Known pitfalls

- Comparing a candidate on a new engine version with a baseline measured months ago on an older one; re-run the baseline.
- Letting the server apply a different chat template after an upgrade without noticing; diff the rendered prompt.
- Gating on PPL alone; quantization can keep PPL close while breaking structured output or long-context retrieval.
- Running the candidate with the response cache on, so it reuses baseline outputs.
- Declaring "no difference" from a set too small to show one.

## Official links

- llama.cpp perplexity / KL divergence: https://github.com/ggml-org/llama.cpp/tree/master/tools/perplexity
- vLLM reproducibility: https://docs.vllm.ai/en/latest/usage/reproducibility/
- vLLM batch invariance: https://docs.vllm.ai/en/latest/features/batch_invariance/
- promptfoo CLI (repeat, no-cache, filters): https://www.promptfoo.dev/docs/usage/command-line/
- lm-evaluation-harness: https://github.com/EleutherAI/lm-evaluation-harness
