# Eval strategy

> Verified against promptfoo 0.124.1 docs (test cases, assertions, filters), 2026-10-11

How to decide what to measure, how big the eval set should be, and how to keep it trustworthy over time. Tool mechanics live in `promptfoo.md` and `lm-eval-harness.md`.

## Start from the decision

Every eval answers one question. Write it down first:

| Decision                                                   | Eval type                              | Primary signal                            |
| ---------------------------------------------------------- | -------------------------------------- | ----------------------------------------- |
| Which model for this product feature?                      | Task eval on a golden set, N providers | Pass rate on critical items, then overall |
| Is this quantization / spec-decode / KV-dtype change safe? | A/B quality gate                       | Per-item flips vs baseline noise          |
| Did this prompt or code change break anything?             | Regression eval in CI                  | No new failures on critical items         |
| How does the model compare publicly?                       | Standard benchmark                     | Benchmark metric, as context only         |
| Is the endpoint wired correctly?                           | Smoke eval (5–10 items)                | All pass, outputs readable                |

If the question is not on this list, it is probably a monitoring question (`llm-observability`) rather than an eval.

## Golden set design

A golden set is a versioned file of real inputs plus checkable expectations.

**Sources, in order of value:**

1. Production inputs that failed or were escalated.
2. Representative production inputs sampled across categories.
3. Edge cases written by domain experts (long inputs, ambiguous requests, refusals, multilingual).
4. Synthetic items, only to fill specific gaps, and labelled `source: synthetic`.

**Expectations should be properties, not essays.** Prefer:

- a fact or identifier that must appear (`icontains`, `contains-all`),
- a format (`is-json` with a schema, `regex`, `starts-with`),
- a forbidden output (`not-icontains`, `not-regex`, `is-refusal` / `not-is-refusal`),
- a tool call shape (`is-valid-openai-tools-call`),
- only then a rubric (`llm-rubric` with a `threshold`).

**Metadata on every item** (promptfoo test `metadata`): `source`, `category`, `critical` (`"yes"`/`"no"`; strings, because `--filter-metadata` matches substrings), `added` (date), `owner`. You can then run slices with `--filter-metadata category=billing`.

## Sizing

- **Smoke:** 5–10 items. Proves wiring, prompt format and parsing.
- **PR gate:** 20–100 fast, deterministic items. Must run in minutes.
- **Decision set:** 100–500 items covering every category you care about.
- **Benchmarks:** full public tasks, run rarely; use `--limit` for smoke runs.

Small sets are noisy. With 50 items, one flip moves the pass rate by two points. That is why decisions use per-item flips and a baseline-vs-baseline noise run (see `quality-gates.md`), not a single aggregate number.

## Slicing and weighting

- Report pass rate per category and for `critical: "yes"` items separately.
- Use promptfoo `weight` on assertions and named `metric` tags to build per-dimension scores (format, correctness, safety).
- A model that wins overall but loses on a critical slice is not a winner.

## Provenance and hold-out

- Keep the golden set in version control with a `README` or header comment stating where items came from and who may edit them.
- Never use golden-set items as few-shot examples in production prompts, and never include them in fine-tuning data. If an item leaks, move it to a "retired" file and replace it.
- Keep a private hold-out split (`split: holdout` in metadata) that is only run before major decisions.
- Strip PII before an item enters the set. If you must keep sensitive inputs, store the eval set and its outputs with the same access controls as production data.

## Growing the set

- Every production incident or user-reported bad answer becomes a new item.
- Every eval failure you decide to accept ("known limitation") is marked in metadata so it does not block CI forever.
- Review the set quarterly: remove duplicates, retire items that no longer reflect the product.

## Reading results

1. Read failing outputs before reading the score.
2. Check that failures are model failures, not assertion bugs (wrong expected value, brittle regex).
3. Compare per-item flips between baseline and candidate.
4. Only then look at aggregate pass rate and cost/latency columns.

## Known pitfalls

- Testing only "happy path" items; real traffic is messier.
- Expected values copied from the current model's output, which bakes its mistakes into the set.
- One giant aggregate score hiding a regression in a small critical category.
- Golden sets that silently drift because anyone can edit them.

## Official links

- promptfoo test cases (JSONL format): https://www.promptfoo.dev/docs/configuration/test-cases/
- promptfoo assertions and metrics: https://www.promptfoo.dev/docs/configuration/expected-outputs/
- promptfoo CLI filters: https://www.promptfoo.dev/docs/usage/command-line/
