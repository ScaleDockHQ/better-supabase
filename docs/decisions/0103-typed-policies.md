# 0103: Block modules emit typed policies

- Status: accepted
- Date: 2026-10-25

## Context

`applyTenantScope`, the actor write guards and the definer guard rewrite SQL text with regular
expressions. They miss dollar quotes, `E''` strings, `for all` and `to public`, and they fail
without any error.

## Decision

A `Policy` is `{ table, name, command, roles, permissive, using, check }`, built by
`policy()` in `src/sql/policy.ts` and rendered to `create policy` in one place. Block modules emit
`Policy` values. The tenant scope, the actor guard and the covered-policy filter compose on those
values, and the regex passes are deleted once no module emits raw policy SQL. The generated files
stay byte-identical; goldens guard that.

A user-written policy reaches the same shape through a rule DSL: a rule
tree renders to a policy plus an `@bsb rule` comment that reads back into the builder. Raw SQL
policies are kept verbatim and pass the same verifier.

## Alternatives considered

- A SQL tokenizer for the rewrites: it fixes the quoting gaps but keeps text as the source of
  truth.

## Consequences

A module author writes `policy({...})`, not `create policy` text. A lint rule rejects raw
`create policy` in block modules.

## Status note

The policy reader and renderer (`src/sql/policy.ts`) serve the covered-policy
filter, the tenant scope and the actor guard. The goldens did not change.
The block modules still write 279 `create policy` statements by hand, in 118
files. `tests/sql/raw-policies.test.ts` ratchets that count against
`raw-policies.baseline.json`: it refuses new raw policies and asks for the
baseline to drop as a module moves to `renderPolicy`.

## Update: every block module emits `Policy` values

The raw `create policy` statements in block modules now go through `policy()` and `renderPolicy()`, and the ratchet baseline is gone: `tests/sql/raw-policies.test.ts` allows none. The installed SQL changes layout only (one clause per line); the set of `drop policy` statements is the same.
