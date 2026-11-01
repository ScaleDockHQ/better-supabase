# 0178: Prompts are versioned templates behind labels, read as the service role

- Status: accepted
- Date: 2026-11-01

## Context

Apps keep prompts in code, so changing one is a deploy and a rollback is a revert. The `agents`,
`ai-schedules` and `ai-cache` blocks all take prompt text but nothing versions it. The LLM skills
(`llm-evals`, `llm-observability`) assume a prompt has a version and a label to compare runs against.

## Decision

A `prompts` block keeps `prompt_versions` and `prompt_labels`. A version is immutable and numbered
per tenant and name under an advisory lock. A label (`production`, `staging`) points at one version,
and `get_prompt` reads `production` unless told otherwise. A prompt with no tenant is a system prompt;
a tenant's prompt of the same name wins. Templates use `{{name}}` placeholders, and `renderPrompt`
inserts values as text and throws on a missing or unused variable.

Like `ai-cache`, the block is service role only, because a template can hold instructions that users
must not read. It has no extra columns, events or permission keys. `ai-evals` and `ai-guardrails`
(plan tracks 1b and 1c) build on the version id.

## Consequences

- A prompt change, promotion and rollback need no deploy.
- The block adds no dependency and no template language, so there is nothing to sandbox.
- A tenant that edits prompts in a UI needs an app route that calls the service client.
