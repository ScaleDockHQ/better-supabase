# 0184: ai-evals runs datasets against a prompt version and a model

- Status: accepted
- Date: 2026-11-01

## Context

Prompts are versioned (ADR 0178), but nothing tells an app whether a new version or model is better
than the last. Rated replies in `ai-chat` (`ai_message_feedback`) are the best source of test cases,
and they stay unused.

## Decision

An `ai-evals` block keeps `eval_datasets`, `eval_items`, `eval_runs` and `eval_results`. A run names a
prompt (`prompt_name`, `prompt_version`) and a model as plain values, so it does not require the
`prompts` block. The block calls no model: `createEvalJob` takes a `task` function, and scorers are
functions. `exactMatch` and `jsonSchema` (Standard Schema) are built in. `llmJudge` takes an injectable
judge port with `apiVersion: 1` and the app supplies the model call. `compare_eval_runs` runs in SQL and
reports regressions and improvements per item. `exportPromptfoo` returns a promptfoo config as JSON.

`add_eval_items_from_feedback` copies rated ai-chat replies into a dataset when `ai-chat` is installed.
This is how feedback reaches a dataset, so the `ai-chat` SQL and client stay unchanged. Like `prompts`,
the block is service role only, because inputs and outputs hold user content.

## Consequences

- A prompt or model change can be compared on the same cases before it ships.
- The block adds no dependency and no model provider.
- The job processes items under a time budget and continues when the same payload is enqueued again.
- A tenant UI for datasets needs an app route that calls the service client.
