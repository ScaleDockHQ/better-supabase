# 0185: ai-guardrails keeps per-agent policies and a hashed decision log

- Status: accepted
- Date: 2026-11-01

## Context

Agents take user text and return model text. Apps need a place to say which agent may see PII, which
topics are off limits and how deep a tool chain may go, and a record of what was stopped.

## Decision

An `ai-guardrails` block keeps `guardrail_policies` (per tenant, agent and stage, with `*` for every
agent) and `guardrail_decisions`. `check` is TypeScript over built-in heuristics: prompt-injection
patterns for OWASP LLM01 on input, PII detection with Luhn and IBAN checksums, topic deny lists and a
tool depth limit. A decision is `allow`, `redact` or `block`. The log stores a SHA-256 hash of the text
and never the text. A block records the `guardrail.blocked` event through the outbox.

`guardrailMiddleware` wraps one model step as text in and text out, so it needs no AI SDK import. It
never changes a repository `Result` (invariant 5), and a failed log write never changes the decision.
A check that cannot run blocks unless the caller sets `failOpen`. Heuristics are not a complete
defence, and the docs say so.

## Consequences

- A policy change needs no deploy.
- The log holds no user content, so it can be kept longer than chats (`retention`).
- An AI SDK middleware adapter can be added later on top of `check`.
