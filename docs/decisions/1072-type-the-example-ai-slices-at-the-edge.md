# 1072: Type the example's AI slices at the edge (lane Y6, EX-310)

- Status: accepted
- Date: 2026-11-15

## Context

Five anti-slop rules were off for the example's AI folders: conditional empty
spreads (30 findings), `unknown` parameters and returns, `typeof` checks and
`Record<string, unknown>` dictionaries (21 findings together). The folders pass
optional fields to block APIs under `exactOptionalPropertyTypes` and read
untyped AI SDK parts, tool outputs and numeric jsonb values.

## Decision

- `src/lib/present.ts` returns the entries of an object that are not
  `undefined`, so an optional input is passed as `...present({ label })`
  instead of a conditional spread.
- Each reader of an untyped value parses it with a valibot schema (the tour's
  chosen direction, the `askQuestions` input, a token count, a model's text
  output, a key's priority) instead of narrowing it with `typeof`.
- The override in `apps/examples/nextjs/oxlint.config.ts` is gone, so the five
  rules apply to the AI folders like the rest of the example.

## Consequences

- The example lints without exceptions. No library API changes.
- A new reader of an AI SDK part follows the same schema pattern.
